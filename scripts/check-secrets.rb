#!/usr/bin/env ruby
# Offline contracts only: ciphertext shape does not prove decryption or readiness.
require 'yaml'
require 'base64'

module PublicationSecrets
  SENTINEL = 'PUBLICATION_ONLY_NOT_A_CIPHERTEXT'.freeze
  ANNOTATION = 'medha.dev/publication-only'.freeze
  REQUIRED = {
    'backend' => %w[database-url s3-access-key s3-secret-key minio-access-key minio-secret-key admin-username admin-password admin-api-token resend-api-key messagecentral-customer-id messagecentral-key-base64 messagecentral-email mapmyindia-client-id mapmyindia-client-secret],
    'postgres' => %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB],
    'redis' => %w[REDIS_PASSWORD REDIS_URL],
    'seaweedfs' => %w[s3-identity-config]
  }.freeze

  def self.required_keys(resource, namespace)
    extra = if resource == 'backend'
              namespace == 'prod' ? %w[credentials-encryption-key firebase-service-account-json] : %w[dev-pandit-phone dev-yajman-phone]
            else
              []
            end
    REQUIRED.fetch(resource) + extra
  end

  def self.secret_name(resource, namespace)
    resource == 'backend' ? "backend-#{namespace}-secrets" : "#{resource}-secrets"
  end

  def self.parse(text)
    stream = Psych.parse_stream(text)
    raise ArgumentError, 'exactly one YAML document required' unless stream.children.length == 1
    inspect_node = lambda do |node|
      raise ArgumentError, 'YAML aliases are not accepted' if node.is_a?(Psych::Nodes::Alias)
      if node.is_a?(Psych::Nodes::Mapping)
        keys = node.children.each_slice(2).map do |key, _|
          raise ArgumentError, 'mapping keys must be scalars' unless key.is_a?(Psych::Nodes::Scalar)
          key.value
        end
        raise ArgumentError, 'duplicate YAML mapping key' unless keys.uniq.length == keys.length
      end
      (node.children || []).each { |child| inspect_node.call(child) } if node.respond_to?(:children)
    end
    inspect_node.call(stream)
    YAML.safe_load(text)
  end

  def self.errors(document, mode:, resource:, namespace:)
    return ['document must be a mapping'] unless document.is_a?(Hash)
    metadata = document['metadata']
    spec = document['spec']
    return ['metadata and spec must be mappings'] unless metadata.is_a?(Hash) && spec.is_a?(Hash)
    template = spec['template']
    return ['template metadata must be a mapping'] unless template.is_a?(Hash) && template['metadata'].is_a?(Hash)
    template = template['metadata']
    annotations = metadata.fetch('annotations', {})
    return ['annotations must be a mapping'] unless annotations.is_a?(Hash)

    errors = []
    errors << 'expected SealedSecret API version' unless document['apiVersion'] == 'bitnami.com/v1alpha1'
    errors << 'expected SealedSecret' unless document['kind'] == 'SealedSecret'
    errors << 'namespace mismatch' unless metadata['namespace'] == namespace && template['namespace'] == namespace
    name = secret_name(resource, namespace)
    errors << 'secret name mismatch' unless metadata['name'] == name && template['name'] == name
    encrypted = spec['encryptedData']
    return errors + ['encryptedData must be a nonempty mapping'] unless encrypted.is_a?(Hash) && !encrypted.empty?

    missing = required_keys(resource, namespace) - encrypted.keys
    errors << "missing required keys: #{missing.join(', ')}" unless missing.empty?
    if mode == :publication
      errors << 'missing publication-only annotation' unless annotations[ANNOTATION] == 'true'
      errors << 'retained ciphertext or mixed fixtures' unless encrypted.values.all? { |value| value == SENTINEL }
    elsif mode == :runtime
      errors << 'publication fixture is not deployable' if annotations.key?(ANNOTATION)
      encrypted.each do |key, value|
        begin
          decoded = Base64.strict_decode64(value.to_s)
          valid = decoded.bytesize >= 128 && decoded.getbyte(0) == 2
        rescue ArgumentError
          valid = false
        end
        errors << "#{key}: not a sealed ciphertext-shaped value" unless valid
      end
    else
      errors << 'unknown validation mode'
    end
    errors
  end
end

if $PROGRAM_NAME == __FILE__
  mode = { '--publication' => :publication, '--runtime' => :runtime }[ARGV.first]
  abort 'usage: ruby scripts/check-secrets.rb --publication|--runtime' unless mode && ARGV.length == 1
  root = File.expand_path('..', __dir__)
  errors = []
  %w[dev prod].each do |namespace|
    PublicationSecrets::REQUIRED.each_key do |resource|
      path = File.join(root, 'kubernetes', 'overlays', namespace, "#{resource}-sealed-secret.yaml")
      begin
        document = PublicationSecrets.parse(File.read(path))
        PublicationSecrets.errors(document, mode: mode, resource: resource, namespace: namespace).each do |error|
          errors << "#{namespace}/#{resource}: #{error}"
        end
      rescue StandardError => error
        errors << "#{namespace}/#{resource}: #{error.class} reading fixture"
      end
    end
  end
  abort errors.join("\n") unless errors.empty?
  puts(mode == :publication ? 'publication secret contracts passed; fixtures are intentionally NOT deployable' : 'ciphertext structure passed only; decryption, credentials and live readiness NOT verified')
end

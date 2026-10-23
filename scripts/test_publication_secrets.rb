require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative 'check-secrets'

class PublicationSecretsTest < Minitest::Test
  def fixture(resource = 'postgres', namespace = 'dev', mode = :publication)
    name = PublicationSecrets.secret_name(resource, namespace)
    doc = {
      'apiVersion' => 'bitnami.com/v1alpha1', 'kind' => 'SealedSecret',
      'metadata' => { 'name' => name, 'namespace' => namespace },
      'spec' => {
        'template' => { 'metadata' => { 'name' => name, 'namespace' => namespace } },
        'encryptedData' => PublicationSecrets.required_keys(resource, namespace).to_h { |key| [key, PublicationSecrets::SENTINEL] }
      }
    }
    if mode == :publication
      doc['metadata']['annotations'] = { PublicationSecrets::ANNOTATION => 'true' }
    else
      # Deliberately fake envelope; shape is NOT decryption verification.
      doc['spec']['encryptedData'].transform_values! { Base64.strict_encode64("\x02" + 'x' * 128) }
    end
    doc
  end

  def errors(doc, mode = :publication, resource = 'postgres', namespace = 'dev')
    PublicationSecrets.errors(doc, mode: mode, resource: resource, namespace: namespace)
  end

  def test_all_resource_environment_contracts_and_each_missing_key
    %w[dev prod].each do |namespace|
      PublicationSecrets::REQUIRED.each_key do |resource|
        [:publication, :runtime].each do |mode|
          doc = fixture(resource, namespace, mode)
          assert_empty errors(doc, mode, resource, namespace)
          PublicationSecrets.required_keys(resource, namespace).each do |key|
            broken = Marshal.load(Marshal.dump(doc))
            broken['spec']['encryptedData'].delete(key)
            expected = broken['spec']['encryptedData'].empty? ? 'encryptedData must be a nonempty mapping' : "missing required keys: #{key}"
            assert_includes errors(broken, mode, resource, namespace), expected
          end
        end
      end
    end
  end

  def test_runtime_rejects_publication_fixture
    assert_includes errors(fixture, :runtime), 'publication fixture is not deployable'
  end

  def test_missing_annotation_fails_publication
    doc = fixture
    doc['metadata'].delete('annotations')
    assert_includes errors(doc), 'missing publication-only annotation'
  end

  def test_mixed_ciphertext_and_fixture_fails_publication
    doc = fixture
    doc['spec']['encryptedData']['POSTGRES_PASSWORD'] = Base64.strict_encode64("\x02" + 'x' * 128)
    assert_includes errors(doc), 'retained ciphertext or mixed fixtures'
  end

  def test_removing_annotation_does_not_make_placeholder_deployable
    doc = fixture
    doc['metadata'].delete('annotations')
    assert_includes errors(doc, :runtime), 'POSTGRES_PASSWORD: not a sealed ciphertext-shaped value'
  end

  def test_namespace_name_and_api_version_are_exact
    doc = fixture
    doc['metadata']['name'] = doc['spec']['template']['metadata']['name'] = 'renamed'
    assert_includes errors(doc), 'secret name mismatch'
    doc = fixture
    doc['spec']['template']['metadata']['namespace'] = 'prod'
    assert_includes errors(doc), 'namespace mismatch'
    doc = fixture
    doc['apiVersion'] = 'invalid/v1'
    assert_includes errors(doc), 'expected SealedSecret API version'
  end

  def test_malformed_values_fail_for_the_specific_value_not_annotation
    ['', 'Ag-invalid-base64', Base64.strict_encode64('short')].each do |value|
      doc = fixture('postgres', 'dev', :runtime)
      assert_empty errors(doc, :runtime)
      doc['spec']['encryptedData']['POSTGRES_PASSWORD'] = value
      assert_equal ['POSTGRES_PASSWORD: not a sealed ciphertext-shaped value'], errors(doc, :runtime)
    end
  end

  def test_malformed_containers_fail_closed
    assert_equal ['document must be a mapping'], errors([])
    ['metadata', 'spec'].each do |key|
      doc = fixture
      doc[key] = 'invalid'
      assert_equal ['metadata and spec must be mappings'], errors(doc)
    end
    doc = fixture
    doc['spec']['encryptedData'] = []
    assert_includes errors(doc), 'encryptedData must be a nonempty mapping'
  end

  def test_extra_document_duplicate_keys_and_aliases_are_rejected
    text = YAML.dump(fixture)
    assert_equal fixture, PublicationSecrets.parse(text)
    assert_raises(ArgumentError) { PublicationSecrets.parse(text + "---\nkind: Secret\n") }
    assert_raises(ArgumentError) { PublicationSecrets.parse("kind: SealedSecret\nkind: Secret\n") }
    assert_raises(ArgumentError) { PublicationSecrets.parse("outer:\n  key: one\n  key: two\n") }
    assert_raises(ArgumentError) { PublicationSecrets.parse("one: &x test\ntwo: *x\n") }
    assert_raises(ArgumentError) { PublicationSecrets.parse('') }
  end

  def test_cli_rejects_missing_files
    Dir.mktmpdir('medha-missing-fixtures') do |root|
      FileUtils.mkdir_p(File.join(root, 'scripts'))
      script = File.join(root, 'scripts', 'check-secrets.rb')
      FileUtils.cp(File.join(__dir__, 'check-secrets.rb'), script)
      _stdout, stderr, status = Open3.capture3('ruby', script, '--publication')
      refute status.success?
      assert_includes stderr, 'Errno::ENOENT reading fixture'
      assert_equal 8, stderr.lines.count
    end
  end

  def test_required_contract_covers_nonoptional_secret_key_consumers
    names = { 'backend-secrets' => 'backend', 'backend-dev-secrets' => 'backend', 'backend-prod-secrets' => 'backend', 'postgres-secrets' => 'postgres', 'redis-secrets' => 'redis', 'seaweedfs-secrets' => 'seaweedfs' }
    visit = lambda do |value|
      if value.is_a?(Hash)
        ref = value['secretKeyRef']
        if ref.is_a?(Hash) && ref['optional'] != true && names.key?(ref['name'])
          resource = names.fetch(ref['name'])
          namespace = ref['name'] == 'backend-dev-secrets' ? 'dev' : 'prod'
          assert_includes PublicationSecrets.required_keys(resource, namespace), ref['key']
        end
        value.each_value { |child| visit.call(child) }
      elsif value.is_a?(Array)
        value.each { |child| visit.call(child) }
      end
    end
    root = File.expand_path('..', __dir__)
    Dir.glob(File.join(root, 'kubernetes', '**', '*.yaml')).each do |path|
      next if path.end_with?('-sealed-secret.yaml')
      YAML.load_stream(File.read(path)).each { |doc| visit.call(doc) }
    end
  end
end

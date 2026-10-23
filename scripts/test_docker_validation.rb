require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class DockerSyntaxValidationTest < Minitest::Test
  def test_syntax_error_in_second_script_is_not_ignored
    Dir.mktmpdir('medha-syntax-test') do |root|
      FileUtils.mkdir_p(File.join(root, 'scripts'))
      FileUtils.mkdir_p(File.join(root, 'docker', 'scripts'))
      validator = File.join(root, 'scripts', 'validate-docker-split.sh')
      FileUtils.cp(File.join(__dir__, 'validate-docker-split.sh'), validator)
      File.write(File.join(root, 'docker', 'scripts', '01-valid.sh'), "#!/bin/bash\ntrue\n")
      File.write(File.join(root, 'docker', 'scripts', '02-invalid.sh'), "#!/bin/bash\nif then\n")
      _stdout, stderr, status = Open3.capture3('bash', validator)
      refute status.success?, 'every script must be parsed, not only the first'
      assert_includes stderr, '02-invalid.sh'
    end
  end
end

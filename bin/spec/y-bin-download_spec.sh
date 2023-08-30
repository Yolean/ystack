

echo "NOTE these tests are unmaintained, were used for early development"

Describe 'y-bin-download'

  Include 'y-bin-download'


  Describe 'gotemplate'

    It 'emulates gotemplate for basic key=value pairs'
      When call gotemplate 'test{{ .v }}foo{{ .xy }}' xy XYvalue
      The output should eq 'test{{ .v }}fooXYvalue'
    End

  End

  # TODO tests for other platforms
  Describe 'identify linux os'

    It 'os() returns os'
      When call os
      The output should eq 'linux'
    End

    It 'arch() returns as golang GOARCH'
      When call arch
      The output should eq 'amd64'
    End

    It 'xarch() returns the uname variant'
      When call xarch
      The output should eq 'x86_64'
    End

  End

  Describe 'binyaml'
    tmp=$(mktemp)

    It 'checks that the given file exists'
      When call binyaml ./nonexistent
      The error should eq 'bin yaml not found at path ./nonexistent'
      The status should eq 1
    End

    It 'extracts the yaml part for the named bin'
      When call binyaml ./y-bin.runner.yaml yq
      The output should match pattern "  version:*"
    End

    It 'extracts the yaml part for the named bin'
      When call binyaml ./y-bin.optional.yaml k3d
      The output should match pattern "*sha256sum.txt"
    End
  End

  Describe 'names'

    It 'lists all bin names'
      When call names ./y-bin.optional.yaml
      The output should match pattern "yq*"
      The output should match pattern "*kustomize*"
    End

  End

  Describe 'binpath'

  End

  Describe 'update'
    Mock install
      printenv
    End

    Mock binyaml
      [ "$2" != "mybin" ] && echo "Expected bin name mybin" && return 1
      echo '
        version: 3.7.1
        sha256:
          linux_amd64: 6cd6cad4b97e10c33c978ff3ac97bb42b68f79766f1d2284cfd62ec04cd177f4
        archive: tgz
        templates:
          download: https://get.helm.sh/helm-v{{ .version }}-{{ .os }}-{{ .arch }}.tar.gz
      '
    End

    It 'parses yaml and calls install'
      When call update mybin2
      The output should match pattern "asfd"
    End

  End

End

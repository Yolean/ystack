Describe 'y-image-bump'
  It 'has a help subcommand'
    When run command y-image-bump help
    The output should include "BUMP_INCLUDE='--include="
  End

  tmp=$(mktemp -d)

  It 'runs the image-bump-example folder recursively'
    cp -r ./spec/image-bump-example/* $tmp/
    y-image-bump yolean/toil e0c572a0643fb7bfee9eb9775870cc412911319c $tmp

    When run command diff -u ./spec/image-bump-example/variations.yaml $tmp/variations.yaml
    The status should eq 1
    The output should include '
-image1: "yolean/toil:2804b31514bdf162fa3ac527cdb5b1b1cfd4d986"
-image2: yolean/toil:2804b31514bdf162fa3ac527cdb5b1b1cfd4d986
+image1: "yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d"
+image2: yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d
 # not git ref tagged, should be skipped
 image3: "yolean/toil"
 image4: yolean/toil
 image5: yolean/toil:123
 # should get a new tag+sha
-image6: yolean/toil:0000000000000000000000000000000000000000@sha256:0000000000000000000000000000000000000000000000000000000000000000
+image6: yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d
 # when other URLs change in this particular file we update instances of the same sha256 as well, see also preserve-sha256.yaml
-image7: yolean/toil:0000000000000000000000000000000000000000@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d
+image7: yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d
 # correct already, should not change
 image8: yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d
 # with host
-image9: "docker.io/yolean/toil:ac196cb3f08b15d2b8c6731533f9ab29a8629389@sha256:3c52b5ddac2c1da52eced6f727e530cef18ea9bd6ae0799505d2b9d81b750aeb"
+image9: "docker.io/yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d"
 # host should be preserved but for now the REGISTRY env must be given to change where we look up digest
-image10: "builds-registry.ystack.svc.cluster.local/yolean/toil:ac196cb3f08b15d2b8c6731533f9ab29a8629389@sha256:3c52b5ddac2c1da52eced6f727e530cef18ea9bd6ae0799505d2b9d81b750aeb"
+image10: "builds-registry.ystack.svc.cluster.local/yolean/toil:e0c572a0643fb7bfee9eb9775870cc412911319c@sha256:700eaa5dcdf8ef01a43150f4d9aa970590f326c3834b7035a56d955a6705f32d"'
  End

  It 'preserved tags that had the same digest'
    When run command diff -s -u ./spec/image-bump-example/preserve-sha256.yaml $tmp/preserve-sha256.yaml
    The output should include "are identical"
  End
End

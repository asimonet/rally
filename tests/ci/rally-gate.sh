#!/bin/bash -ex
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# This script is executed by post_test_hook function in desvstack gate.

PROJECT=`echo $ZUUL_PROJECT | cut -d \/ -f 2`

RALLY_JOB_DIR=$BASE/new/$PROJECT/rally-scenarios
if [ ! -d $RALLY_JOB_DIR ]; then
    RALLY_JOB_DIR=$BASE/new/$PROJECT/rally-jobs
fi

echo $RALLY_JOB_DIR
echo $RALLY_DIR
ls $BASE/new/$PROJECT

BASE_FOR_TASK=${RALLY_JOB_DIR}/${RALLY_SCENARIO}

TASK=${BASE_FOR_TASK}.yaml
TASK_ARGS=""
if [ -f ${BASE_FOR_TASK}_args.yaml ]; then
    TASK_ARGS=" --task-args-file ${BASE_FOR_TASK}_args.yaml"
fi

PLUGINS_DIR=${RALLY_JOB_DIR}/plugins
EXTRA_DIR=${RALLY_JOB_DIR}/extra

RALLY_PLUGINS_DIR=~/.rally/plugins

mkdir -p $RALLY_PLUGINS_DIR
if [ -d $PLUGINS_DIR ]; then
    cp -r $PLUGINS_DIR/ $RALLY_PLUGINS_DIR
fi

if [ -d $EXTRA_DIR ]; then
 mkdir -p ~/.rally/extra
 cp -r $EXTRA_DIR/* ~/.rally/extra/
 touch ~/.rally/extra/fake-image.img
fi

env
set -o pipefail
rally deployment use --deployment devstack
rally deployment config
rally --debug deployment check
source ~/.rally/openrc
if rally deployment check | grep 'nova' | grep 'Available' > /dev/null; then
    nova flavor-create m1.nano 42 64 0 1
fi

# TODO(stpierre): We should prepopulate the cluster with a wide
# variety of resources to ensure that Rally cleanup isn't overzealous,
# but in the meantime this solves an issue with resource
# comparison. When the first instance is booted, default security
# groups are created in the 'service' tenant, and they were being
# reported (erroneously) in the resource comparison. This forces
# creation of those security groups before we record the initial
# resources, and also starts us along the path of prepopulating
# resources.
nova boot --image cirros-0.3.4-x86_64-uec --flavor m1.tiny --poll test-server

python $BASE/new/rally/tests/ci/osresources.py\
    --dump-list resources_at_start.txt

rally -v --rally-debug task start --task $TASK $TASK_ARGS

mkdir -p rally-plot/extra
python $BASE/new/rally/tests/ci/render.py ci/index.mako > rally-plot/extra/index.html
cp $TASK rally-plot/task.txt
tar -czf rally-plot/plugins.tar.gz -C $RALLY_PLUGINS_DIR .
rally task results | python -m json.tool > rally-plot/results.json
gzip -9 rally-plot/results.json
rally task detailed > rally-plot/detailed.txt
gzip -9 rally-plot/detailed.txt
rally task detailed --iterations-data > rally-plot/detailed_with_iterations.txt
gzip -9 rally-plot/detailed_with_iterations.txt
rally task report --out rally-plot/results.html
gzip -9 rally-plot/results.html

# NOTE(stpierre): if the sla check fails, we still want osresources.py
# to run, so we turn off -e and save the return value
set +e
rally task sla_check | tee rally-plot/sla.txt
retval=$?
set -e

cp resources_at_start.txt rally-plot/
python $BASE/new/rally/tests/ci/osresources.py\
    --compare-with-list resources_at_start.txt\
        | gzip > rally-plot/resources_diff.txt.gz

exit $retval

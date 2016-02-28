#!/bin/bash
# Copyright 2015 Google, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This init script installs Apache Zeppelin on the master node of a Cloud
# Dataproc cluster. Zeppelin is also configured based on the size of your
# cluster and the versions of Spark/Hadoop which are installed.
set -x -e

# Get executor memory value
EXECUTOR_MEMORY="$(grep spark.executor.memory /etc/spark/conf/spark-defaults.conf | awk '{print $2}')"

# Set these Spark and Hadoop versions based on your Dataproc version
SPARK_VERSION="1.5.2"
HADOOP_VERSION="2.7.1"
ZEPPELIN_VERSION="0.6.0-incubating"

# Only run on the master node
ROLE="$(/usr/share/google/get_metadata_value attributes/dataproc-role)"
if [[ "${ROLE}" == 'Master' ]]; then
  # 1. Python
  apt-get -y install python-pip
  apt-get -y install python-dev
  apt-get -y install python-matplotlib

  # 2. Python wordcloud
  pip install Image
  wget https://github.com/amueller/word_cloud/archive/master.zip
  unzip master.zip
  rm -f master.zip
  pushd word_cloud-master
  pip install -r requirements.txt
  python setup.py install
  popd

  # 3. Font
  gsutil cp gs://fc_auto_zeppelin/CabinSketch-Bold.ttf /usr/share/fonts/
  chmod 644 /usr/share/fonts/CabinSketch-Bold.ttf
  fc-cache -fv

  # 4. Data files
#  pushd /tmp
#  gsutil cp gs://fc_auto_zeppelin/kddcupsmall /tmp/
#  gsutil cp gs://fc_auto_zeppelin/text8_lines? /tmp/
#  hadoop fs -mkdir /data
#  hadoop fs -put /tmp/kddcupsmall /data/
#  hadoop fs -put /tmp/text8_lines? /data/
#  rm -f kddcupsmall
#  rm -f text8_lines?
#  popd

  # 5. Zeppelin
  gsutil cp gs://fc_auto_zeppelin/zeppelin-${ZEPPELIN_VERSION}-SNAPSHOT.tar.gz /usr/lib/
  cd /usr/lib/
  mkdir -p /usr/lib/incubator-zeppelin
  tar zxf zeppelin-${ZEPPELIN_VERSION}-SNAPSHOT.tar.gz -C /usr/lib/incubator-zeppelin --strip-components=1
  rm -f zeppelin-${ZEPPELIN_VERSION}-SNAPSHOT.tar.gz

  cd incubator-zeppelin
  mkdir -p logs run conf
  cat > conf/zeppelin-env.sh <<EOF
#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

export MASTER="yarn-client" # Spark master url. eg. spark://master_addr:7077. Leave empty if you want to use local mode.
export ZEPPELIN_JAVA_OPTS="-Dhdp.version=$HADOOP_VERSION" # Additional jvm options. for example, export ZEPPELIN_JAVA_OPTS="-Dspark.executor.memory=8g -Dspark.cores.max=16"

#### Spark interpreter configuration ####

## Use provided spark installation ##
## defining SPARK_HOME makes Zeppelin run spark interpreter process using spark-submit
##

export SPARK_HOME="/usr/lib/spark" # (required) When it is defined, load it instead of Zeppelin embedded Spark libraries
export SPARK_SUBMIT_OPTIONS="--executor-memory $EXECUTOR_MEMORY" # (optional) extra options to pass to spark submit. eg) "--driver-memory 512M --executor-memory 1G".

## Use embedded spark binaries ##
## without SPARK_HOME defined, Zeppelin still able to run spark interpreter process using embedded spark binaries.
## however, it is not encouraged when you can define SPARK_HOME
##

export HADOOP_CONF_DIR="/etc/hadoop/conf" # yarn-site.xml is located in configuration directory in HADOOP_CONF_DIR.

## Pyspark (supported with Spark 1.2.1 and above)
## To configure pyspark, you need to set spark distribution's path to 'spark.home' property in Interpreter setting screen in Zeppelin GUI
##

export PYSPARK_PYTHON="/usr/bin/python" # path to the python command. must be the same path on the driver(Zeppelin) and all workers.
export PYTHONPATH="/usr/bin/python"

## Spark interpreter options ##
##
# export ZEPPELIN_SPARK_USEHIVECONTEXT  # Use HiveContext instead of SQLContext if set true. true by default.
export ZEPPELIN_SPARK_CONCURRENTSQL   # Execute multiple SQL concurrently if set true. false by default.
# export ZEPPELIN_SPARK_MAXRESULT       # Max number of SparkSQL result to display. 1000 by default.

EOF

  cp /etc/hive/conf/hive-site.xml conf/
  chmod -R a+w conf logs run

  # Let Zeppelin create the conf/interpreter.json file
  /usr/lib/incubator-zeppelin/bin/zeppelin-daemon.sh start
  /usr/lib/incubator-zeppelin/bin/zeppelin-daemon.sh stop

  # Force the spark.executor.memory to be inherited from the environment
  sed -i 's/"spark.executor.memory": "512m",/"spark.executor.memory": "",/' /usr/lib/incubator-zeppelin/conf/interpreter.json
  /usr/lib/incubator-zeppelin/bin/zeppelin-daemon.sh start
fi

set +x +e

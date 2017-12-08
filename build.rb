#!/opt/elasticbeanstalk/lib/ruby/bin/ruby
#encoding: utf-8

# Copyright 2015-2015 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
# except in compliance with the License. A copy of the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under the License.

require 'json'
require 'open3'
require 'aws-sdk'
require 'open-uri'

# get the region that the instance is running in
$region = JSON.parse(open('http://169.254.169.254/latest/dynamic/instance-identity/document').read)["region"]

# create a new DynamoDB client
$ddb = Aws::DynamoDB::Client.new({ region: $region })

def main
  # read environment variables using the get-config utility
  env_vars = JSON.parse(%x(/opt/elasticbeanstalk/bin/get-config environment))

  # read the Elastic Beanstalk deployment manifest
  dep_manifest = JSON.parse(File.read('/tmp/manifest'))

  # read the private IP of the instance from the metadata service
  private_ip = open('http://169.254.169.254/latest/meta-data/local-ipv4').read
  
  # get the number of CPU cores available
  num_cores = get_num_cores()

  eb_env_name = env_vars["EB_ENV_NAME"]
  master_ip_table = env_vars["MASTER_IP_TABLE"]
  deployment_id = dep_manifest["DeploymentId"]

  # Use DynamoDB conditional update to select a master and save it's IP.
  # Only a single instance will be able to update the record, all others
  # will fail the conditional check
  is_master = write_master_ip(master_ip_table, eb_env_name, private_ip, deployment_id)

  puts "We are " + (is_master ? "master" : "follower")

  if is_master
    # since this instance is the master, save 127.0.0.1 as the master IP
    # to be used by the follower processes
    File.open('.masterIP', "w") { |f| f.print "127.0.0.1" }

    # write .foreman file with a single master process and the number of cores
    # available minus 1 follower processes
    File.open('.foreman', "w") { |f| f.print "concurrency: locust-master=1,locust-follower=#{num_cores - 1}" }
  else
    # since this instance is a follower, get the master IP from the DynamoDB table
    master_ip = get_master_ip(master_ip_table, eb_env_name)

    if master_ip
      # save the master IP to be used by the follower processes
      File.open('.masterIP', "w") { |f| f.print "#{master_ip}" }

      # update the nginx.conf to use the master instances IP for upstream
      run_command('sed -i -e "s|\(.*\)http://\(.*\):\(.*\)|\1http://' + master_ip + ':\3|g" '\
                  '.ebextensions/nginx/nginx.conf')
    end

    # write the .foreman file with zero master processes and number of cores
    # available follower proceses
    File.open('.foreman', "w") { |f| f.print "concurrency: locust-master=0,locust-follower=#{num_cores}" }
  end

  # Recreate the application.conf since we have modified the .foreman file
  run_command('HOME=/tmp /opt/elasticbeanstalk/lib/ruby/bin/ruby '\
              '/opt/elasticbeanstalk/lib/ruby/bin/foreman export supervisord '\
              '--procfile /var/app/staging/Procfile --root /var/app/current '\
              '--app application --log /var/log/ --user webapp '\
              '--template /opt/elasticbeanstalk/private/config/foreman/supervisord '\
              '--env /var/elasticbeanstalk/staging/elasticbeanstalk.env '\
              '/var/elasticbeanstalk/staging/supervisor')
end

def get_num_cores()
  num_cores ||= begin
    cpuinfo = File.read('/proc/cpuinfo')
    cpuinfo.scan(/^processor\s*:/).count
  rescue Exception => e
    puts "Error getting CPU cores"
    puts e.message
  end
end

def run_command(command)
  output, status = Open3.capture2e(command)
  puts "#{command}"

  if output.length > 1
    puts "#{output}"
  end
end

def get_num_instances_in_environment(env_name)
  begin
    eb = Aws::ElasticBeanstalk::Client.new({ region: $region })
    resp = eb.describe_environment_resources(:environment_name => env_name)
    if resp
      return resp.environment_resources.instances.count
    end
  rescue Exception => e
    puts "Error retrieving number of instances in #{env_name}"
    puts e.message
  end
end

def write_master_ip(table_name, key, ip, deployment_id)
  begin
    update_time = Time.now()
    instance_id = open('http://169.254.169.254/latest/meta-data/instance-id').read
    num_instances = get_num_instances_in_environment(key)

    $ddb.update_item(
      :table_name => table_name,
      :key => { :HashKey => key },
      :update_expression => "SET IP = :val, ChangedAt = :time, ReadCount = :rc, 
                             DeploymentID = :dep_id, InstanceID = :inst_id",
      :condition_expression => "attribute_not_exists(DeploymentID) OR DeploymentID < :dep_id",
      :expression_attribute_values => {
        ":rc" => 0,
        ":val" => ip,
        ":time" => update_time.to_s,
        ":inst_id" => instance_id,
        ":dep_id" => deployment_id
      }
    )

    return true

  rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
    return false
  rescue Exception => e
    puts "Error writing master IP to #{table_name}"
    puts e.message
  end
end

def get_master_ip(table_name, key)
  5.downto(1) do |retries|
    begin
      sleep(3 * (5 - retries))
      puts "Read Attempt #{6 - retries}"

      item = $ddb.get_item(
        :table_name => table_name,
        :key => { :HashKey => key }
      ).data.item

      if item
        $ddb.update_item(
          :table_name => table_name,
          :key => { :HashKey => key },
          :update_expression => "ADD ReadCount :val",
          :expression_attribute_values => {":val" => 1}
        )

        return item["IP"]
      end
    rescue Exception => e
      puts "Error reading master IP from #{table_name}"
      puts e.message
    end
  end
end

main if __FILE__==$0

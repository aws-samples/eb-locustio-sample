# AWS Elastic Beanstalk Load Generator Example
This sample application uses the [Locust](http://locust.io/) open source load testing tool to create a simple load generator for your applications. The sample test definition *[locustfile.py](locustfile.py)* tests the root of an endpoint passed in as an environment variable *(TARGET_URL)*. For more information on the format of the test definition file, see [Writing a locustfile](http://docs.locust.io/en/latest/writing-a-locustfile.html).

You can get started using the following steps:
  1. [Install the AWS Elastic Beanstalk Command Line Interface (CLI)](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-install.html).
  2. Create an IAM Instance Profile named **aws-elasticbeanstalk-locust-role** with the policy in [policy.json](policy.json). For more information on how to create an IAM Instance Profile, see [Create an IAM Instance Profile for Your Amazon EC2 Instances](https://docs.aws.amazon.com/codedeploy/latest/userguide/how-to-create-iam-instance-profile.html).
  3. Run `eb init -r <region> -p "Java 8"` to initialize the folder for use with the CLI. Replace `<region>` with a region identifier such as `us-west-2` (see [Regions and Endpoints](https://docs.amazonaws.cn/en_us/general/latest/gr/rande.html#elasticbeanstalk_region) for a full list of region identifiers). For interactive mode, run `eb init` then,
     1. Pick a region of your choice.
     2. Select the **[ Create New Application ]** option.
     3. Enter the application name of your choice.
     4. Answer **no** to *It appears you are using Python. Is this correct?*.
     5. Select **Java** as the platform.
     6. Select **Java 8** as the platform version.
     7. Choose whether you want SSH access to the Amazon EC2 instances.  
        *Note: If you choose to enable SSH and do not have an existing SSH key stored on AWS, the EB CLI requires ssh-keygen to be available on the path to generate SSH keys.*  
  4. Run `eb create -i c4.large --scale 1 --envvars TARGET_URL=<test URL> --instance_profile aws-elasticbeanstalk-locust-role` to begin the creation of your load generation environment. Replace `<test URL>` with the URL of the web app that you want to test.
  *Note: If you don't have a default VPC (most AWS accounts created in 2014 or later should have a default VPC in the account) in your account, please substitue the above instance type with c3.large.*
     1. Enter the environment name of your choice.
     2. Enter the CNAME prefix you want to use for this environment.
  5. Once the environment creation process completes, run `eb open` to open the [Locust](http://locust.io/) dashboard and start your tests.
  6. To make changes to the test definition, edit the *[locustfile.py](locustfile.py)*, save and commit the changes, and run `eb deploy`.
  7. If you'd like to scale out the environment to more than 1 EC2 instance,
     1. Run `eb scale <number of instances>`. Replace `<number of instances>` with the number of EC2 instances you would like the environment to scale out to.
     2. If you are reducing the number of running instances in the above step, run `eb deploy` to reselect the master instance removal has been completed.
     3. Run `eb open` to open the [Locust](http://locust.io/) dashboard and start your tests.
  8. When you are done with your tests, run `eb terminate --all` to clean up.

*Note: Running Locust in distributed mode requires a master/slave architecture. This sample requires that the auto scaling minimum and maximum be set to the same value to ensure that the master isn't terminated by auto scaling. If for some reason the master instance is replaced, an `eb deploy` should be all it takes to fix it.*

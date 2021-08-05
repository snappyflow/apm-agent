##### Python etl feature 

* To run python script, ProjectName and appName should be present.
* Please provide config as mentione below,
```
key: provide_key
tags:
  Name: name
  appName: appName
  projectName: projectName
metrics:
  plugins:
    - name: etl
      enabled: true
      url:
        job: provide_job_url 
        stage: provide_stage_url
        task: provide_task_url
        authkey: provide_authentication_key_for_the_urls
      buffer_path: /utility/bufferdata.json     #provide path for bufferfile which keeps record of unfinished job,stage and tasks. 
```
* Please mention the config file path in main.py file
* After this setup, add cronjob into /etc/crontab
	ex: To run script every 5 minutes 
	 -  */5 * * * * root python /home/ubuntu/python_script/utility/main.py

 * please refer this link for cronjob
	https://www.digitalocean.com/community/tutorials/how-to-use-cron-to-automate-tasks-ubuntu-1804

Note:

* Suppose if we want to add another plugin to this then add the plugin details in the config file in the plugins and create your new input file in the input folder. 
* The input python file name should always be same as the plugin name.
* The code inside the input file should start with "work" fuction with plugin_config parameter
* The work fuction should return list of dictionary objects.










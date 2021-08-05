##### Python etl feature 

* To run python script, ProjectName and appName should be present.
* Please provide config as mentione below,
```
key: <profile key>
tags: 
  Name: <name>
  appName: <appName>
  projectName: <projectName>
metrics:
  plugins:
    - name: <PluginName>
      enabled: true
      url:
        job: <job_url> 
        stage: <stage_url>
        task: <task_url>
        authkey: <authentication_key_for_the_urls>
      buffer_path: <path for bufferfile.json>     #provide path for bufferfile which keeps record of unfinished job,stage and tasks. 
```
* Please mention the config file path in main.py file
* After this setup, add cronjob into /etc/crontab( Applicable for Linux AWS instance, else run this script as a cron job)
	ex: To run script every 5 minutes 
	 -  */5 * * * * root python /home/ubuntu/python_script/utility/main.py

 * please refer this link for cronjob
	https://www.digitalocean.com/community/tutorials/how-to-use-cron-to-automate-tasks-ubuntu-1804

Note:

* If we want to add another plugin to this, add the plugin details in the config file under the plugins section and create your new input file in the input folder. 
* The input python file name should always be same as the plugin name. In this case plugin name is "etl".
* There should be a fuction named "work" with config parameter which will be invoked when we run the script. 
* The work fuction should return list of dictionary objects.










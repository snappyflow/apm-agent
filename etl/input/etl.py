import schedule
import time
import ast
import os
import json 
import requests

def get_data(urlDict):
    jobsUrl = urlDict["job"]
    stagesUrl = urlDict["stage"]
    tasksUrl = urlDict["task"]
    all_data = []
    for url in [jobsUrl,stagesUrl,tasksUrl]:
        response = requests.get(
            url,
            # params={'duration': '10d'},
            headers={'Authorization': urlDict["authkey"],'Content-type': 'application/json' },
            verify=False
        )
        data = json.loads(response.text)
        # data = ast.literal_eval(json.dumps(data))
        
        all_data = all_data + data.get("result", [])
    return all_data


def create_mapping(data):
    
    start_stages = {}
    success_stages = {}
    truncate_stages = {}

    start_tasks = {}
    success_tasks = {}
    truncate_tasks = {}

    all_jobs = {i["jobId"]:{} for i in data if i["type"]=="job"}
    all_stages = {i["stageId"]:{} for i in data if i["type"] == "stage"}

    for k,_ in all_jobs.items():
        temp_start_stage = {}
        temp_success_stage = {}
        temp_truncate_stage = {}

        task_stage_start_map = {}
        task_stage_success_map = {}
        task_stage_truncate_map = {}


        for stage,_ in all_stages.items():
            temp_success_tasks = {}
            temp_start_tasks = {}
            temp_truncate_tasks = {}
            for j in data:
                if j["type"] == "stage" and j["status"] == "success" and k == j["jobId"]:
                    temp_start_stage.update({j["stageId"]: {"status":j["status"],"time":j["time"]}})
                elif j["type"] == "stage" and j["status"] == "started" and k == j["jobId"]:
                    temp_success_stage.update({j["stageId"]: {"status":j["status"],"time":j["time"]}})
                elif j["type"] == "stage" and j["status"] in ["failed","aborted"] and k == j["jobId"]:
                    temp_truncate_stage.update({j["stageId"]: {"status":j["status"],"time":j["time"]}})
                    
                if j["type"] == "task" and j["status"] == "success" and stage == j["stageId"] and k == j["jobId"]:
                    temp_success_tasks.update({j["taskId"]:{"status":j["status"],"time":j["time"]}})

                if j["type"] == "task" and j["status"] == "started" and stage == j["stageId"] and k == j["jobId"]:
                    temp_start_tasks.update({j["taskId"]:{"status":j["status"],"time":j["time"]}})

                if j["type"] == "task" and j["status"]  in ["failed","aborted"] and stage == j["stageId"] and k == j["jobId"]:
                    temp_truncate_tasks.update({j["taskId"]:{"status":j["status"],"time":j["time"]}})
                
                    
            task_stage_start_map.update({stage: temp_start_tasks})
            task_stage_success_map.update({stage:temp_success_tasks })
            task_stage_truncate_map.update({stage: temp_truncate_tasks})
           
            start_tasks.update({k:task_stage_start_map})
            success_tasks.update({k:task_stage_success_map})
            truncate_tasks.update({k:task_stage_truncate_map})

            success_stages.update({k:temp_start_stage}) 
            start_stages.update({k:temp_success_stage})
            truncate_stages.update({k:temp_truncate_stage})    
            
    start_tasks = {i:j for i,j in start_tasks.items() if i in list(all_jobs.keys())}
    success_tasks = {i:j for i,j in success_tasks.items() if i in list(all_jobs.keys())}
    return start_stages,success_stages,truncate_stages,start_tasks,success_tasks,truncate_tasks

def work(metricConfig):

    # data = []

    #GET LOGS FROM ES
    # with open('input/crondata.json' ) as f:
    #     datalogs = json.load(f) 
    datalogs = get_data(metricConfig.get("url",{}))

    bufferPath = metricConfig.get("buffer_path","bufferdata.json")
    if os.path.exists(bufferPath):
        with open(bufferPath, "r") as f:
            try:
                prev_data = json.load(f)
            except ValueError: 
                prev_data = []

        datalogs = ast.literal_eval(json.dumps(prev_data)) + datalogs
        with open(bufferPath, "w") as fl:
            # json.dumps(datalogs , fl)
            fl.write(json.dumps(datalogs))
    else:
        with open(bufferPath, "w") as fl:
            json.dump(datalogs,fl)

    #Take updated buffered data
    with open(bufferPath,"r") as fla:
            try:
                data = json.load(fla)
            except ValueError: 
                data = []

    data = ast.literal_eval(json.dumps(data))

    if data:

        start_jobs = {record["jobId"]:record["time"] for record in data if record["type"] == "job" and record["status"] == "started"}
        success_jobs = {record["jobId"]:record["time"] for record in data if record["type"] == "job" and record["status"] == "success"}
        truncate_jobs = {record["jobId"]:record["time"] for record in data if record["type"] == "job" and record["status"] in ["aborted","failed"]}
        

        start_stages, success_stages ,truncate_stages, start_tasks, success_tasks,truncate_tasks = create_mapping(data)

        final_jobs = []
        final_stages = []
        final_tasks = []
        for record in data:

            if record["type"] == "task" and record["status"] == "success":
                if record["taskId"] in list((success_tasks.get(record["jobId"],{})).get(record["stageId"],{}).keys()):
                    localdict = {}
                    localdict["taskName"] = record["taskName"]
                    localdict["taskId"] = record["taskId"]
                    localdict["jobId"] = record["jobId"]
                    localdict["stageId"] = record["stageId"]
                    localdict["jobName"] = record["jobName"]
                    localdict["stageName"] = record["stageName"]
                    localdict["startTime"] = start_tasks.get(record["jobId"],{}).get(record["stageId"],{}).get(record["taskId"],{}).get("time",0)
                    localdict["endTime"] = success_tasks.get(record["jobId"],{}).get(record["stageId"],{}).get(record["taskId"],{}).get("time",0)
                    localdict["status"] = "success"
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = "task"     
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_tasks.append(localdict)

                if  record["taskId"] in list(truncate_tasks.get(record["jobId"],{}).get(record["stageId"],{}).keys()):
                    localdict = {}
                    localdict["taskName"] = record["taskName"]
                    localdict["taskId"] = record["taskId"]
                    localdict["jobId"] = record["jobId"]
                    localdict["stageId"] = record["stageId"]
                    localdict["jobName"] = record["jobName"]
                    localdict["stageName"] = record["stageName"]
                    localdict["startTime"] = start_tasks.get(record["jobId"],{}).get(record["stageId"],{}).get(record["taskId"],{}).get("time",0)
                    localdict["endTime"] = truncate_tasks.get(record["jobId"],{}).get(record["stageId"],{}).get(record["taskId"],{}).get("time",0)
                    localdict["status"] = record["status"]
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = "task"    
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    localdict["description"] = "Task is either failed or aborted"
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_tasks.append(localdict)
                    

                    
            
            if record["type"] == "stage" and record["status"] == "success":
                if record["stageId"] in list(success_stages.get(record["jobId"],{}).keys()):
                    localdict = {}
                    localdict["stageName"] = record["stageName"]
                    localdict["stageId"] = record["stageId"]
                    localdict["jobId"] = record["jobId"]
                    localdict["jobName"] = record["jobName"]
                    localdict["startTime"] = start_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0)   
                    localdict["endTime"] = success_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0)    
                    localdict["status"] = "success"
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = "stage"     
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_stages.append(localdict)

                    tasks_under_stage = [i["taskId"] for i in data if i["type"] == "task" and i["stageId"] == record["stageId"] and i["jobId"] == record["jobId"]]
                    current_success_task = [i for i,_ in success_tasks[record["jobId"]][record["stageId"]].items() if i in tasks_under_stage]
                    current_running_task = {i["taskId"]:{"name":i["taskName"],"time":i["time"] } for i in data if i["type"] == "task" and not i["taskId"] in current_success_task and  i["stageId"] == record["stageId"] and i["jobId"] == record["jobId"] }
                    if len(tasks_under_stage) != len(current_success_task):
                        for current_task, value in current_running_task.items():
                            localdict = {}
                            localdict["taskName"] = value["name"] 
                            localdict["taskId"] = current_task
                            localdict["stageId"] = record["stageId"]
                            localdict["stageName"] = record["stageName"]
                            localdict["jobId"] = record["jobId"]
                            localdict["jobName"] = record["jobName"]
                            localdict["startTime"] = value["time"]
                            localdict["endTime"] = success_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0)       
                            localdict["status"] = "success"
                            localdict["time"] = localdict["endTime"] 
                            localdict["type"] = "task"    
                            localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                            localdict["description"] = "Current task is closed, since the parent stage is success"
                            if localdict["endTime"] != 0 and localdict["startTime"] != 0:                       
                                final_tasks.append(localdict)
                            
            if record["type"] == "stage" and record["status"] in ["failed","aborted"]:
                if  record["stageId"] in list(truncate_stages.get(record["jobId"],{}).keys()):
                    localdict = {}
                    localdict["stageName"] = record["stageName"]
                    localdict["stageId"] = record["stageId"]
                    localdict["jobId"] = record["jobId"]
                    localdict["startTime"] = start_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0)
                    localdict["endTime"] = truncate_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0) 
                    localdict["status"] = record["status"]
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = record["type"]     
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    localdict["description"] = "Stage is either failed or aborted"
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_stages.append(localdict)

                    tasks_under_stage = [i["taskId"] for i in data if i["type"] == "task" and i["stageId"] == record["stageId"] and i["jobId"] == record["jobId"]]
                    current_success_task = [i for i,_ in success_tasks[record["jobId"]][record["stageId"]].items() if i in tasks_under_stage]
                    current_running_task = {i["taskId"]:{"name":i["taskName"],"time":i["time"] } for i in data if i["type"] == "task" and not i["taskId"] in current_success_task and  i["stageId"] == record["stageId"] and i["jobId"] == record["jobId"] }
                    if len(tasks_under_stage) != len(current_success_task):
                        for current_task, value in current_running_task.items():
                            localdict = {}
                            localdict["taskName"] = value["name"] 
                            localdict["taskId"] = current_task
                            localdict["stageId"] = record["stageId"]
                            localdict["stageName"] = record["stageName"]
                            localdict["jobId"] = record["jobId"]
                            localdict["jobName"] = record["jobName"]
                            localdict["startTime"] = value["time"]
                            localdict["endTime"] = truncate_stages.get(record["jobId"],{}).get(record["stageId"],{}).get("time",0)       
                            localdict["status"] = record["status"]
                            localdict["time"] = localdict["endTime"] 
                            localdict["type"] = "task"    
                            localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                            localdict["description"] = "Current task is closed, since the parent stage is aborted or failed"
                            if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                                final_tasks.append(localdict)

                                    
            if record["type"] == "job":
                #calculate duration of job
                if record["jobId"] in list(success_jobs.keys()) and record["status"] == "success":
                    localdict = {}
                    localdict["jobName"] = record["jobName"]
                    localdict["jobId"] = record["jobId"]
                    localdict["startTime"] = start_jobs.get(record["jobId"], 0)
                    localdict["endTime"] = success_jobs.get(record["jobId"], 0)
                    localdict["status"] = "success"
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = "job"    
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_jobs.append(localdict)

                    current_stage_list = [i["stageId"] for i in data if i["type"] == "stage" and i["jobId"] == record["jobId"]  ]
                    current_success_stage = [i for i,_ in success_stages[record["jobId"]].items() if i in current_stage_list]
                    current_running_stage = {i["stageId"]:{"name":i["stageName"], "time": i["time"]} for i in data if i["type"] == "stage" and not i["stageId"]  in current_success_stage and  i["jobId"] == record["jobId"]}

                    if len(current_stage_list) != len(current_success_stage):
                        for current_stage, value in  current_running_stage.items():
                            localdict = {}
                            localdict["stageName"] = value["name"]
                            localdict["stageId"] = current_stage
                            localdict["jobId"] = record["jobId"]
                            localdict["jobName"] = record["jobName"]
                            localdict["startTime"] = value["time"]
                            localdict["endTime"] = success_jobs.get(record["jobId"], 0) 
                            localdict["status"] = "success"
                            localdict["time"] = localdict["endTime"] 
                            localdict["type"] = "stage"   
                            localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                            localdict["description"] = "Stage is closed ,since the parent job is success"
                            if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                                final_stages.append(localdict)


                            tasks_under_stage = [{i["taskId"]:i["status"]} for i in data if i["type"] == "task" and i["stageId"] == current_stage and i["jobId"] == record["jobId"]]    
                            current_success_task = [i for i,_ in success_tasks[record["jobId"]].get(current_stage,{}).items() if i in tasks_under_stage]
                            current_running_task = {i["taskId"]:{"name":i["taskName"],"time":i["time"] } for i in data if i["type"] == "task" and not i["taskId"] in current_success_task and i["stageId"] == current_stage and i["jobId"] == record["jobId"]}
                            if len(tasks_under_stage) != len(current_success_task):
                                for current_task, val in current_running_task.items():
                                    localdict = {}
                                    localdict["taskName"] = val["name"] 
                                    localdict["taskId"] = current_task
                                    localdict["stageId"] = current_stage
                                    localdict["stageName"] = value["name"]
                                    localdict["jobId"] = record["jobId"]
                                    localdict["jobName"] = record["jobName"]
                                    localdict["startTime"] = val["time"]
                                    localdict["endTime"] = success_jobs.get(record["jobId"], 0)     
                                    localdict["status"] = "success"
                                    localdict["time"] = localdict["endTime"] 
                                    localdict["type"] = "task"    
                                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                                    localdict["description"] = "Task is closed ,since the parent stage is success"
                                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                                        final_tasks.append(localdict)
                
                if record["jobId"] in list(truncate_jobs.keys()):
                    localdict = {}
                    localdict["jobName"] = record["jobName"]
                    localdict["jobId"] = record["jobId"]
                    localdict["startTime"] = start_jobs.get(record["jobId"], 0)
                    localdict["endTime"] = truncate_jobs.get(record["jobId"], 0)
                    localdict["status"] = "success"
                    localdict["time"] = localdict["endTime"] 
                    localdict["type"] = record["type"]     
                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                    localdict["description"] = "Job is either aborted or failed"
                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                        final_jobs.append(localdict)

                    current_stage_list = [i["stageId"] for i in data if i["type"] == "stage" and i["jobId"] == record["jobId"]  ]
                    current_success_stage = [i for i,_ in success_stages[record["jobId"]].items() if i in current_stage_list]
                    current_running_stage = {i["stageId"]:{"name":i["stageName"], "time": i["time"]} for i in data if i["type"] == "stage" and not i["stageId"]  in current_success_stage and  i["jobId"] == record["jobId"]}

                    if len(current_stage_list) != len(current_success_stage):
                        for current_stage, value in  current_running_stage.items():
                            localdict = {}
                            localdict["stageName"] = value["name"]
                            localdict["stageId"] = current_stage
                            localdict["jobId"] = record["jobId"]
                            localdict["jobName"] = record["jobName"]
                            localdict["startTime"] = value["time"]
                            localdict["endTime"] = truncate_jobs.get(record["jobId"], 0) 
                            localdict["status"] = record["status"]
                            localdict["time"] = localdict["endTime"] 
                            localdict["type"] = "stage"   
                            localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                            localdict["description"] = "Stage is closed ,since the parent job is failed or aborted"
                            if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                                final_stages.append(localdict)


                            tasks_under_stage = [{i["taskId"]:i["status"]} for i in data if i["type"] == "task" and i["stageId"] == current_stage and i["jobId"] == record["jobId"]]    
                            current_success_task = [i for i,_ in success_tasks[record["jobId"]].get(current_stage,{}).items() if i in tasks_under_stage]
                            current_running_task = {i["taskId"]:{"name":i["taskName"],"time":i["time"] } for i in data if i["type"] == "task" and not i["taskId"] in current_success_task and i["stageId"] == current_stage and i["jobId"] == record["jobId"]}
                            if len(tasks_under_stage) != len(current_success_task):
                                for current_task, val in current_running_task.items():
                                    localdict = {}
                                    localdict["taskName"] = val["name"] 
                                    localdict["taskId"] = current_task
                                    localdict["stageId"] = current_stage
                                    localdict["stageName"] = value["name"]
                                    localdict["jobId"] = record["jobId"]
                                    localdict["jobName"] = record["jobName"]
                                    localdict["startTime"] = val["time"]
                                    localdict["endTime"] = truncate_jobs.get(record["jobId"], 0)    
                                    localdict["status"] = record["status"]
                                    localdict["time"] = localdict["endTime"] 
                                    localdict["type"] = "task"    
                                    localdict["duration"] = localdict["endTime"] - localdict["startTime"]
                                    localdict["description"] = "Task is closed ,since the parent stage is failed or aborted"
                                    if localdict["endTime"] != 0 and localdict["startTime"] != 0:
                                        final_tasks.append(localdict)
        
        #POST DATA TO ES
        all_data = final_jobs + final_stages + final_tasks
        
        #Update buffer file
        result = []
        start_stages1, success_stages1 ,truncate_stages1, start_tasks1, success_tasks1,truncate_tasks1 = create_mapping(all_data)
        job_list = [i["jobId"] for i in final_jobs if i["status"] == "success"]
        for rec in data:
            if rec.get("taskId",0) and rec["type"] == "task":

                if not rec["taskId"] in list(success_tasks1.get(rec["jobId"],{}).get(rec["stageId"],{}).keys()) and rec["stageId"] in list(success_tasks1.get(rec["jobId"],{}).keys()) and rec["jobId"] in job_list:

                    result.append(rec)
            if rec.get("stageId",0) and rec["type"] == "stage" and rec["jobId"] in job_list:
                if not rec["stageId"] in list(success_stages1.get(rec["jobId"],{}).keys()):
                    result.append(rec)
            if rec.get("jobId",0) and rec["type"] == "job":
                if not rec["jobId"] in list(success_jobs.keys()):
                    result.append(rec)

        #print("unfinished_to_buffer : ",len(result))
        #print("success_jobs       : ",len(final_jobs))
        #print("success_stages     : ",len(final_stages))
        #print("success_tasks      : ",len(final_tasks))
        #print("\n")

        
        with open(bufferPath, "w") as fl:
            json.dump(result,fl) 

        return all_data
    else:
        return []



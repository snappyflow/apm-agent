import output.pushtoES as op
import os
import yaml
import time
import schedule
import sys


def main():
    config = {}
    configFile = "/home/ubuntu/python_script/etl/config.yaml"
    try:
        # if os.path.isfile("config.yaml"):
        with open(configFile) as file:
            config = yaml.load(file)
                # logger.info(config)
    except Exception as exception:
        # logger.error("error in opening config.yaml")
        # logger.error(exception)
        print("error in opening config.yaml")


    res = []

    for metric in config.get("metrics",{}).get("plugins"):
        exec("from input import %s" %metric["name"])
        metric_data = eval(metric["name"]+".work")(metric)
        if metric["enabled"]:
            for doc in metric_data:
                doc["_plugin"] =  metric["name"]
                doc["_documentType"]  = metric["name"]+"Success"
                doc["_tag_Name"] = config.get("tags",{}).get("Name","")
                doc["_tag_appName"] = config.get("tags",{}).get("appName","")
                doc["_tag_projectName"] = config.get("tags",{}).get("projectName","")
                doc["time"] = int(time.time() * 1000)
            metric_data = [op.iterateDict(i) for i in metric_data]
            res.append(op.write_docs_bulk(config,metric_data))
if __name__ == "__main__":
    main()


import base64
from Crypto.Cipher import AES
from urlparse import urlparse
import ast
from elasticsearch import helpers
from elasticsearch import Elasticsearch
import json
import os
import sys
import yaml
from scriptConst import Constants
import requests



def iterateDict(data):
    local_dict = {}
    for key,val in data.items():
        if type(val) == unicode:
            local_dict[key.encode("utf-8")] = val.encode("utf-8")
        elif type(val) != dict:
            local_dict.update({key.encode("utf-8"):val})
        elif type(val) == dict:
            local_dict.update({key.encode("utf-8"):iterateDict(val)})
        else:
            local_dict.update({key.encode("utf-8"):val})
    return local_dict




def decrypt(enc):
    def unpad(raw_data):
        return raw_data[:-ord(raw_data[len(raw_data)-1:])]
    enc = base64.b64decode(enc)
    iv = enc[:16]
    cipher = AES.new(Constants.decrypt_key, AES.MODE_CBC, iv)
    return unpad(cipher.decrypt( enc[16:] ))

def prepare_data( target, data):

    DOCUMENTTYPE = Constants._DOC
    docs = []
    config = target.get(Constants.CONFIG, {})
    if config and config.get(Constants.ENABLED):
        index = target[Constants.CONFIG][Constants.INDEX]
        for document in data:
            doc = {}
            doc[Constants._INDEX] = index + Constants._WRITE
            doc[Constants._TYPE] = DOCUMENTTYPE
            doc[Constants._SOURCE] = document
            docs.append(doc)
        return docs
    else:
        # logger.error("Target is not enabled "+target.get(Constants.NAME, ""))
        print("error while forming data")

def get_es_client( target):
    config = target.get(Constants.CONFIG, {})
    if config:
        http_auth = ''
        host = config.get(Constants.HOST)
        port = config.get(Constants.PORT)
        if host:
            scheme = config.get(Constants.PROTOCOL)
            username = config.get(Constants.USERNAME)
            password = config.get(Constants.PASSWORD)
            if password:
                password = base64.b64decode(password)

            if username and password:
                http_auth = (username,password)
            es = Elasticsearch(hosts=[{Constants.HOST: host, Constants.PORT: port}],
                                http_auth=http_auth,
                                scheme=scheme
                                )
            return es
        else:
            # logger.error("Target Dosen't contain host " +
                            # target.get(Constants.NAME, ""))
            print("tagret doesnt contain host")
            return
    else:
        # logger.error("Target Dosen't contain config " +
                        # target.get(Constants.NAME, ""))
        print("target doesnt contain config")
        return

def write_docs_bulk(config,data):

    res1 = get_index_conf(decrypt(config["key"]),config["tags"]["projectName"],'metric' )
    targets = [iterateDict(res1)]
    MAXRETRY = 2
    TIMEOUT = 10
    # response_output = []
    for target in targets:
        
        # target["config"]["password"] = "2330996677315"
        # target["config"]["username"] = "apmuser"
        cfg = target.get(Constants.CONFIG ,{})
        if cfg and cfg.get(Constants.TYPE) == Constants.ELASTICSEARCH:
            es_client = get_es_client(target)
            if not es_client.ping():
                pass
                # raise ValueError("Connection failed")

            docs = prepare_data(target, data)
            if es_client and docs:
                try:
                    res = helpers.bulk(
                        es_client, docs, refresh=True, request_timeout=TIMEOUT, max_retries=MAXRETRY)
                    return res

                except Exception as e:
                    print("Issue with indexing data",e)
                    # logger.error(e)
                    # logger.error("Issue with indexing data")
        else:
            send_docs_to_kafka_rest_proxy(target,data)
    return


def send_docs_to_kafka_rest_proxy(target,data):
    cfg = target.get(Constants.CONFIG ,{})
    if cfg and data:
        url = cfg.get("url","")
        index = cfg.get(Constants.INDEX)

        url = url + "/topics/" + index
        if url:
            username = cfg.get(Constants.USERNAME)
            password = cfg.get(Constants.PASSWORD)
            auth_token = cfg.get(Constants.TOKEN)
            if password:
                password = base64.b64decode(password)
            if auth_token:
                headers = {"Content-Type":"application/vnd.kafka.json.v2+json","Accept":"application/vnd.kafka.v2+json","Authorization":auth_token}
            else:
                headers = {"Content-Type":"application/vnd.kafka.json.v2+json","Accept":"application/vnd.kafka.v2+json"}
            auth=(username,password)
            #preparing payload for kafka
            payload = {}
            payload["records"] = []
            for document in data:
                value = {}
                value["value"]=document
                payload["records"].append(value)
            try:
                r = requests.post(url, data=json.dumps(payload), headers=headers,timeout=5,verify=False)
                print("status", r.status_code)
                if r.status_code !=200:
                    print("Status Code in kafka code: %s" , str(r.status_code))
                    # logger.error("Status Code: %s" , str(r.status_code))
                    # logger.error(r.text)
                
            except Exception as e:
                print("Exception kafka post: %s" , e)
                # logger.error(e)
                # logger.error("Issue with sending data to kafka-rest")
    return

def get_index_conf(conf,project_name = "", plugin_type = ""):
    es_conf = {}
    conf  = json.loads(conf)
    tar_type = conf.get(Constants.TYPE)
    profile_id = conf[Constants.PROFILE_ID]
    owner = conf.get(Constants.OWNER,"")


    if owner:
        # self.owner = owner
        del conf[Constants.OWNER]
    del conf[Constants.PROFILE_ID]
    # name = Constants.CONTROL + "-" + profile_id
    name = plugin_type + "-" + profile_id
    if conf.get(Constants.PASSWORD):
        conf[Constants.PASSWORD] = base64.b64encode(conf[Constants.PASSWORD])
    if tar_type == Constants.ELASTICSEARCH:
        es_conf[Constants.TYPE] = Constants.ELASTICSEARCH
        if plugin_type:
            name = plugin_type + "-" + profile_id + "-" + project_name

    es_conf[Constants.NAME] = name
    conf[Constants.INDEX] = name
    conf[Constants.ENABLED] = True
    es_conf[Constants.CONFIG] = conf
    return es_conf


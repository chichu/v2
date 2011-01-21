#!/usr/bin/python
#encoding:utf-8

import os,sys,re
from mongo import *
from strutils import filter_tags,replace,smart_utf8,get_timestamp

timestamp = get_timestamp(days=1) 
collect = "raw_data_%s" % timestamp

DATA_ROOT = '/data1/dspider/data/bak/%s/'%timestamp

mongodb = MongoUtils()

for pathname in os.listdir(DATA_ROOT):
    path = os.path.join(DATA_ROOT,pathname)
    for filename in os.listdir(path):
        data_file = os.path.join(path,filename)
        repx = re.compile(".+_(?P<date>\d{8})_(?P<time>\d{4})\.txt$")
        date_dict = re.match(repx,filename).groupdict()
        date = date_dict["date"]
        time = date_dict["time"]
        try:
            f = open(data_file,"r")
            column = {}
            while 1:
                line = str(f.readline()).strip()
                if not line:
                    f.close()
                    break
                if line == "@" and bool(column):
                    column['date'] = date
                    column['time'] = time
                    mongnodb.insert(collect,column)
                    column = {}
                    continue
                repx = re.compile("^@(?P<name>\w+):(?P<value>.+)")
                match_str = re.match(repx,line)
                if match_str:
                    tmp_dict = match_str.groupdict()
                    name = tmp_dict['name'].lower()
                    value = tmp_dict['value'].strip()
                    try:
                        value = filter_tags(value).strip()
                        value = replace(value,re.compile("\'|\""),"")
                        value = smart_utf8(value)
                        column[name] = value
                    except Exception,e:
                        print e 
                        continue
        except Exception,e:
            print e

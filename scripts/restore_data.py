#encoding:utf-8

import os,sys,re
from datetime import datetime
from dbutils import DBUtils
from strutils import filter_tags,replace
from django.utils.encoding import smart_str

DATA_ROOT = '/data1/dspider/data/src/'

db = DBUtils()

for pathname in os.listdir(DATA_ROOT):
    path = os.path.join(DATA_ROOT,pathname)
    for filename in os.listdir(path):
        data_file = os.path.join(path,filename)
        try:
            f = open(data_file,"r")
            column = {}
            while 1:
                line = f.readline()
                if not line:
                    f.close()
                    break
                line = str(line).strip()
                if line == "@" and bool(column):
                    repx = re.compile(".+_(?P<date>\d{8})_(?P<time>\d{4})\.txt$")
                    date_dict = re.match(repx,filename).groupdict()
                    column['date'] = date_dict["date"] 
                    column['time'] = date_dict["time"]
                    db.insert("raw_data",column)
                    column = {}
                    continue
                repx = re.compile("^@(?P<name>\w+):(?P<value>.+)")
                match_str = re.match(repx,line)
                if match_str:
                    tmp_dict = match_str.groupdict()
                    name = tmp_dict['name'].lower()
                    value = tmp_dict['value'].strip()
                    try:
                        value = filter_tags(smart_str(value,'utf-8'))
                        value = repalce(value,re.compile("\'|\""),"")
                        column[name] = value
                    except Exception,e:
                        print e 
                        continue
        except Exception,e:
            print e
db.commit()
db.close()
                






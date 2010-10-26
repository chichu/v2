#encoding:utf-8

import os,sys
from dbutils import DBUtils

DATA_ROOT = '/data1/dsipder/data/src/'

#db = DBUtils()

for pathname in os.listdir(DATA_ROOT):
    path = os.path.join(DATA_ROOT,pathname)
    for filename in os.listdir(path):
        data_file = os.path.join(path,filename)
        f = open(data_file,"r")
        column = {}
        while 1:
            line = f.readline()
            if not line:
                break
            elif line == "@":
                #db.insert("raw_data",column)
                print column
                column = {}
                continue
            repx = re.compile("^@(?P<name>.+):(?P<value>.+)")
            if repx:
                name = repx.groupdict()['name'].lower()
                value = repx.groupdict()['value'].strip()
                column[name] = value
#db.commit()
#db.close()
                






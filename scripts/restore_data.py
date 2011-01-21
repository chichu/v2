#!/usr/bin/python
#encoding:utf-8

import os,sys,re
from dbutils import DBUtils
from strutils import filter_tags,replace,smart_utf8,get_timestamp

timestamp = get_timestamp(days=1) 
table_name = "raw_data_%s" % timestamp

CREATE_SQL = """
create table %(table_name)s(      
        id int(11) AUTO_INCREMENT PRIMARY KEY,
        site varchar(255) NOT NULL,
        uid  varchar(255) NULL,
        author varchar(255) NULL,
        channel varchar(255) NULL,
        blogurl varchar(255) NULL,
        blogt  varchar(255) NULL,
        date DATE NULL,
        time TIME NULL,      
        url  varchar(255) NULL,
        keyword varchar(255) NULL,
        title  varchar(255) NULL,
        article TEXT NULL
);\n
create index site_index_%(timestamp)s on %(table_name)s(site);\n
create index date_index_%(timestamp)s on %(table_name)s(date);\n
"""

DATA_ROOT = '/data1/dspider/data/bak/%s/'%timestamp

db = DBUtils()
db.execute_sql(CREATE_SQL%{"table_name":table_name,"timestamp":timestamp})
db.close()

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
                    if column.has_key("udid"):
                        column['uid'] = column['udid']
                        del column['udid']
                    db.insert(table_name,column)
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
            print "Error in restore date:",e
db.close()

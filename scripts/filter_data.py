#!/usr/bin/python
#encoding:utf-8

import os,sys
from datetime import datetime
from dbutils import DBUtils
from strutils import get_timestamp

start_time = datetime.now()

if len(sys.argv) < 2: 
    timestamp = get_timestamp(day_delta=1) 
else:
    timestamp = sys.argv[1] 
table_name = "raw_data_%s" % timestamp

db = DBUtils()

keywords = []
c = db.select(table='brand')
for one in c.fetchall():
    id,name,buss = one
    keywords.append(name)

site_types = {}
c = db.select(table='sites')
for one in c.fetchall():
    id,name,url,site_type = one
    site_types[url] = site_type
print site_types.items()    

cursor = db.select(table=table_name,columns=["count(*)"])
(total,) = cursor.fetchone()
limit = 100
for i in range(0,total,limit):
    cursor = db.select(table=table_name,columns=['id','site','title','article'],limit=limit,start=i)
    for one in cursor.fetchall():
        if not bool(one):break
        (data_id,site,title,article) = one
        if not bool(title) or not bool(article):continue
        site_type = "Unknown"
        if site_types.has_key(site):
            site_type = site_types[site]
        for word in keywords:
            if title.find(word) != -1 or article.find(word) != -1:
                values = {'keywords':word,'site_type':site_type,'timestamp':timestamp,'index_table':table_name,'index_id':data_id}
                print values.items()
                db.insert(table='filtered_data_index',values=values)
db.close()

print start_time,"   ",datetime.now()

#!/usr/bin/python
#encoding:utf-8

import os,sys
from dbutils import DBUtils
from strutils import get_timestamp

timestamp = get_timestamp(day_delta=1) 
table_name = "raw_data_%s" % timestamp

db = DBUtils()

keywords = []
c = db.select(table='brand')
for one in c.fetchall():
    name,buss = one
    keyword.append(name)
print keywords

site_types = {}
c = db.select(table='sites')
for one in c.fetchall():
    name,url,site_type = one
    site_types[url] = site_type
print site_types.items()    

cursor = db.select(table=table_name,columns=['id','site','title','acticle'])
while 1:
    one = cursor.fetchone()
    if not bool(one):break
    (data_id,site,title,acticle) = one
    new_title = title
    new_acticle = acticle
    words = []
    for word in keywords:
        new_title = new_title.replace(word,"<font color=red>%s</font>"%word)
        new_acticle = new_acticle.replace(word,"<font color=red>%s</font>"%word)
        if (len(new_title) != len(title)) or (new_acticle != len(acticle)):
            words.append(word)
    if bool(words):
        values = {'keywords':','.join(words),'site_type':site_types['site'],'timestamp':timestamp,'index_table':table_name,'index_id',data_id}
        db.insert(table='filtered_index_data',values)
    
db.close()

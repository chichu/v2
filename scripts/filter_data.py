#!/usr/bin/python
#encoding:utf-8

import os,sys
from datetime import datetime
from dbutils import DBUtils
from strutils import get_timestamp

print datetime.now()
 
timestamp = get_timestamp(day_delta=1) 
table_name = "raw_data_%s" % timestamp

db = DBUtils()

keywords = []
c = db.select(table='brand')
for one in c.fetchall():
    id,name,buss = one
    keywords.append(name)
print keywords

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
    cursor = db.select(table=table_name,columns=['id','site','title','article'],limit=limit,from=i)
    while 1:
        one = cursor.fetchone()
        print one
        if not bool(one):break
        (data_id,site,title,article) = one
        new_title = title
        new_article = article
        words = []
        for word in keywords:
            new_title = new_title.replace(word,"<font color=red>%s</font>"%word)
            new_article = new_article.replace(word,"<font color=red>%s</font>"%word)
            if (len(new_title) != len(title)) or (new_article != len(article)):
                words.append(word)
        if bool(words):
            site_type = "Unknown"
            if site_types.has_key(site):
                site_type = site_types[site]
            values = {'keywords':','.join(words),'site_type':site_type,'timestamp':timestamp,'index_table':table_name,'index_id':data_id}
            db.insert(table='filtered_index_data',values=values)
db.close()

print datetime.now()

#!/usr/bin/python
#encoding:utf-8

'''
create index site_index on filtered_data_index(site_type);
create index keyword_index on filtered_data_index(keyword);
create index timestamp_index on filtered_data_index(timestamp);
'''
import os,sys
from datetime import datetime
from dbutils import DBUtils
from strutils import get_timestamp

print datetime.now()

if len(sys.argv) < 2: 
    timestamp = get_timestamp(day_delta=1) 
else:
    timestamp = sys.argv[1] 

db = DBUtils()

c = db.execute_sql('select count(*),site_type,keyword,timestamp where timestamp=%s group by keyword,site_type'%timestamp)
for one in c.fetchall():
    count,site_type,timestamp = one
    values = {"timestamp":timestamp,'count':count,'keyword':keyword,'site_type':site_type}
    db.insert('sumdata_byday',values)
db.close()
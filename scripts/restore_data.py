#encoding:utf-8

import os,sys
from dbutil import DBUtils

DATA_ROOT = '/data1/dsipder/data/src/'

for filename in os.path.listdir(DATA_ROOT):
	path = os.path.join(DATA_ROOT,filename)
	f = open(path,"rb")
	while f.readline


db = DBUtils()
db.begin()

db.insert("")

db.commit()



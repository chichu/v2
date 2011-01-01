#encoding:utf-8

from pymongo import Connection,ASCENDING,DESCENDING
from datetime import datetime,timedelta

MONGODB_NAME = "v2"
MONGODB_HOST = "localhost"
MONGODB_USER = "v2"
MONGODB_PASSWORD = "v2@2010"

def get_mongodb_collect(collection,database=MONGODB_NAME):
    db = Connection()[database]
    collect = db[collection]
    return collect

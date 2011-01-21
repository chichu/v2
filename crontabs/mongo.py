#encoding:utf-8

from pymongo import Connection,ASCENDING,DESCENDING
from datetime import datetime,timedelta

DEFAULT_CONN_PARAMS = {
     "name":"v2",
     "host":"localhost",
     "user":"v2",
     "passwd":"v2@2010"
}

class MongoUtils:
    def __init__(self,conn_params=DEFAULT_CONN_PARAMS):
        self.database = conn_params['name']
        
    def get_collect(name):
        db = Connection()[self.database]
        collect = db[name]
        return collect
    
    def insert(col_name,values):
        collect = self.get_collect(col_name)
        try:
            collect.insert(values)
        except Exception,e:
            print e 
            return False
        return True
            
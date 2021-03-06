# -*- coding: utf-8 -*-

DEFAULT_CONN_PARAMS = {
    "host":"localhost",
    "user":"v2",
    "passwd":"v2@2010",
    "db":"v2"
} 

DEFAULT_DB_ENGINE = "MySQLdb"

def join_dict(params,join_str=" and "):
    pairs = get_pairs(params)
    if len(pairs) == 1:
        return pairs[0]
    return join_str.join(pairs)
 
def get_pairs(values):
    pairs = []
    for key,value in values.items():
        if type(value) == "IntType":
            pairs.append("%s=%s"%(key,value))
        else:
            pairs.append("%s='%s'"%(key,value))
    return pairs
   
class DBUtils:
    def __init__(self,db_engine=DEFAULT_DB_ENGINE,conn_params=DEFAULT_CONN_PARAMS,charset='utf8'):
        try:
            module = __import__(db_engine)
            self.conn = module.connect(**conn_params)
            self.cursor = self.conn.cursor()
            self.charset = charset 
        except Exception,e:
            print "Error in init DBUtils:%s" % e
        
    def get_connection(self):
        return self.conn
        
    def get_cursor(self):
        return self.cursor

    def commit(self):
        self.conn.commit()
        
    def close(self):
        self.cursor.close()
        self.conn.close()
    
    def select(self,table,columns="*",condition={},limit=0,start=0):
        sql = "select %s from %s" % (",".join(columns),table)
        if bool(condition):
            sql += " where %s" % join_dict(condition)
        if limit != 0:
            sql += " limit %s,%s" %(start,limit)            
        #print sql
        c = self.cursor.execute(sql)
        return self.cursor 
        
    def insert(self,table,values={}):
        if not bool(table) or not bool(values):return
        self.cursor.execute("set names '%s'"%self.charset)
        sql = "insert into %s set %s" % (table,join_dict(values,","))
        #print sql
        return self.execute_sql(sql)
        
    def update(self,table,values={},condition={}):
        if not bool(table) or not bool(values):return
        sql = "update %s set %s where %s"%(table,join_dict(values,","),join_dict(condition))
        return self.execute_sql(sql)
        
    def delete(self,table,condition={}):
        if not bool(condition):return
        sql = "delete from %s where %s"%(table,join_dict(condition))
        return self.execute_sql(sql)
   
    def execute_sql(self,sql):
        if not bool(sql):return 
        try:
            self.cursor.execute(sql)
        except Exception,e:
            print e 
        return self.cursor

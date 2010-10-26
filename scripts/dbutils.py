# -*- coding: utf-8 -*-

DEFAULT_CONN_PARAMS = {
    "host":"localhost",
    "user":"v2",
    "passwd":"v2@2010",
    "db":"v2"
} 

DEFAULT_DB_ENGINE = "MySQLdb"

def get_condition_sql(params):
    pairs = get_pairs(params)
    if len(pairs) == 1:
        return pairs[0]
    return " and ".join(pairs)
 
def get_pairs(values):
    pairs = []
    for key,value in values.items():
        if type(value) == "IntType":
            pairs.append("%s=%s"%(key,value))
        else:
            pairs.append("%s='%s'"%(key,value))
    return pairs
   
class DBUtils():
    def __init__(self,db_engine=DEFAULT_DB_ENGINE,conn_params=DEFAULT_CONN_PARAMS):
        try:
            module = __import__(db_engine)
            self.conn = module.connect(conn_params)
            self.cursor = module.conn.cursor()
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
    
    def select(self,table,columns="*",condition={}):
        sql = "select %s from %s where %s" % (",".join(columns),table,get_condition_sql(condition)
        return self.cursor.fetchall(sql)
        
    def insert(self,table,values={}):
        sql = "insert into %s set %s" % (table,get_pairs(values))
        return self.cursor.execute(sql)
        
    def update(self,table,values={},condition={}):
        sql = "update %s set %s where %s"%(table,get_pairs(values),get_condition_sql(condition))
        return self.cursor.execute(sql)
        
    def delete(self,table,condition={}):
        sql = "delete from %s where %s"%(table,get_condition_sql(condition))
        return self.cursor.execute(sql)

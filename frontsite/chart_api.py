# encoding: utf-8
"""
chart_api.py

Created by chichu on 2011-01-25.
Copyright (c) 2011 __MyCompanyName__. All rights reserved.
"""

import sys
import os

XML_TEMP = """
    <chart caption='%(chart_title)s' xAxisName='%(x_title)s' yAxisName='%(y_tilte)s' %(options)s>
    %(data_sets)s 
    <trendLines>%(trend_set)s</trendLines>
    </chart>
"""
DATA_SET_TMEP = "<set label='%(lable)s' value='%(value)s' />"
TRAND_TEMP = "<line  displayvalue='%(title)s' startValue='%(value)s' color='009933' />"

def format_str(dict_data,temp):
    tmp = []
    for key,value in dict_data.items():
        tmp.append(temp%(key,value))
    return " ".join(tmp)
    
class XMLGenerator:
    def __init__(self,datas,options={},trend_lines={}):
        self.opt_str = self.data_str = self.trend_str""
        if not bool(options):
            self.opt_str = format_str(options,"%s='%s'")
        if not bool(trend_lines):
            self.trend_str = format_str(trend_lines,TRAND_TEMP)
        self.data_str = format_str(datas,DATA_SET_TMEP)
    
    def generate(self,tilte,x_title,y_title):
        self.XML = XML_TMP % (tilte,x_title,y_title,self.opt_str,self.data_str,self.trend_str)
        return self.XML
    
    
        
        
    
    

if __name__ == '__main__':
    


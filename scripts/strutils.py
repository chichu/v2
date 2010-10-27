#encoding:utf-8

from django.utils.encoding import smart_unicode

def smart_utf8(content):
    try:
        content = smart_unicode(content,"utf8").encode("utf8")
    except:
        content = smart_unicode(content,"gbk").encode("utf8")
    return content

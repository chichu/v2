# Create your views here.
from django.shortcuts import render_to_response
from django.utils.encoding import * 
from django.http import HttpResponse,HttpResponseRedirect, HttpRequest
from v2.admsite.models import *

def index(request):
    the_bussi = request.get("the_bussi",1)
    the_brand = request.get("the_brand",1)
    bussiness = Bussiness.objects.all()
    brands = Brand.objects.filter(buss=the_bussi)
    return render_to_response('frontsite/index.html',locals())

def get_brand_bybuss(request,bussi_id):
    bussi = Bussiness.object.get(id=bussi_id)
    brands = bussi.brand_set.all()
    html = ""
    for brand in brands:
        html += "<option value='%s'>%s</option>" % (brand.id,brand.name)
    return HttpResponse(html)
    
def get_total_xml(request):
    
    return HttpResponse(xml) 
    
def get_bussi_xml(request):
    return HttpResponse(xml)

def get_brand_xml(request):
    return HttpResponse(xml) 
    
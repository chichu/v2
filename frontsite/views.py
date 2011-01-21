# Create your views here.
from django.shortcuts import render_to_response
from django.utils.encoding import * 
from django.http import HttpResponse,HttpResponseRedirect, HttpRequest
from v2.admsite.models import *

def index(request):
    brands = Brand.objects.all()
    return render_to_response('frontsite/index.html',locals())

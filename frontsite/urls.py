from django.conf.urls.defaults import *

urlpatterns = patterns("v2.frontsite.views",
    ('get_brands/$','get_brands_bybussi'),
    ('total_xml/$','get_total_xml'),
    ('bussi_xml/$','get_bussi_xml'),
    ('brand_xml/$','get_brand_xml'),
    (r'^$','index'),
    
)
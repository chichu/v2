from django.conf.urls.defaults import *

# Uncomment the next two lines to enable the admin:
from django.contrib import admin
admin.autodiscover()

urlpatterns = patterns('',
    # Uncomment the next line to enable the admin:
    (r'^admin/', include(admin.site.urls)),
    #to be replace by apache path
    (r'^static/(?P<path>.*)', 'django.views.static.serve',{'document_root': '/home/chichu/v2/media/'}),

    (r'^$', include('v2.frontsite.urls')),
)

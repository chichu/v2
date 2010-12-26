from django.contrib import admin
from models import * 

class BussinessAdmin(admin.ModelAdmin):
    pass
admin.site.register(Bussiness, BussinessAdmin)

class BrandAdmin(admin.ModelAdmin):
    pass
admin.site.register(Brand, BrandAdmin)

class KeywordAdmin(admin.ModelAdmin):
    pass
admin.site.register(Keyword, KeywordAdmin)

class SiteAdmin(admin.ModelAdmin):
    pass
admin.site.register(Site, SiteAdmin)



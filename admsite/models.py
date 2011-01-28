from django.db import models

# Create your models here.

class Bussiness(models.Model):
    name = models.CharField(max_length=10)
    def __unicode__(self):
        return self.name
    class Meta:
        db_table = u'bussiness'
        verbose_name = 'Bussiness'

class Brand(models.Model):
    name = models.CharField(max_length=10)
    buss = models.ForeignKey(Bussiness)
    def __unicode__(self):
        return self.name
    class Meta:
        db_table = u'brand'
        verbose_name = 'Brands'
'''
class Keyword(models.Model):
    words = models.CharField(max_length=100)
    brand = models.ForeignKey(Brand)
    def __unicode__(self):
        return self.words
    class Meta:
        db_table = u'keywords'
'''

class FilteredDataIndex(models.Model):
    index_id = models.IntegerField()
    index_table = models.CharField(max_length=30)
    site_type = models.CharField(max_length=10)
    timestamp = models.IntegerField()
    status = models.CharField(max_length=10,null=True,blank=True,default='00000')
    keyword = models.CharField(max_length=10)
    class Meta:
        db_table = u'filtered_data_index'

class SumDataByDay(models.Model):
    timestamp = models.IntegerField()
    site_type = models.CharField(max_length=10)
    keyword = models.CharField(max_length=10)
    count = models.IntegerField()
    class Meta:
        db_table = u'sumdata_byday'
        
SITE_CLASSIFICATION = (
    ('discuz','Discuz'),
    ('blog','Blog'),
    ('sns','SNS'),
    ('others','Others'),
)
class Site(models.Model):
    name = models.CharField(max_length=20)
    url = models.CharField(max_length=100)
    classi = models.CharField(max_length=10,choices=SITE_CLASSIFICATION)
    def __unicode__(self):
        return self.name
    class Meta:
        db_table = u'sites'
    

import time
from datetime import datetime

search_range = 'SGW'

now = int(time.time())
print(now)

tday = time.strftime('%Y%m%d%H%M', time.localtime(now-486400))
print(tday)
eday = time.strftime('%Y%m%d%H%M', time.localtime(now+486400))
print(eday)

search_date = '/'+search_range+'/'+tday+'/'+eday
print(search_date)

print "=" * 80


_regtime="2023-10-05 14:47"
regtime= int(time.mktime(time.strptime(_regtime, '%Y-%m-%d %H:%M')))
print(regtime)

print("ALLOW_HIST_START_TIME >>>> "+datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S.%f'))

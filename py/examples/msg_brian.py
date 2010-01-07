from perfsonar.message import psMessageBuilder

def makeRequest():
    interfaceInfo = {
    'ifName':'xe-0/0/0',
    'hostName':'albu-sdn1',
    'authRealm':'ESnet-Public',
    'direction':'in'
    }
    requestParams = {
    "startTime":'1254120960',
    "endTime":'1254164160',
    "consolidationFunction":'AVERAGE',
    "resolution":'30'
    }
    
    psm = psMessageBuilder('#message1', 'SetupDataRequest')
    
    psm.addMetadataBlock('#in', subject='#netutil1', subjectType='interface', 
                        subjectData=interfaceInfo,
                        eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0')
                        
    interfaceInfo['direction'] = 'out'
    psm.addMetadataBlock('#out', subject='#netutil1', subjectType='interface', 
                        subjectData=interfaceInfo,
                        eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0')
                        
    psm.addMetadataBlock('#metaIn', subject='#periodIn', paramid='#paramsIn', 
                        params=requestParams,
                        eventType='http://ggf.org/ns/nmwg/ops/select/2.0')
    psm.addMetaIdRef('#periodIn', '#in')
    
    psm.addMetadataBlock('#metaOut', subject='#periodOut', paramid='#paramsOut', 
                        params=requestParams,
                        eventType='http://ggf.org/ns/nmwg/ops/select/2.0')
    psm.addMetaIdRef('#periodOut', '#out')
                        
    psm.addDataBlock('#dataIn', metadataIdRef='#metaIn')
    psm.addDataBlock('#dataOut', metadataIdRef='#metaOut')
    
    print psm.tostring(cleanup=True)
    
    pass
    
def makeResponse():
    responseMeta = {
        'urn':'urn:ogf:network:domain=es.net:node=albu-sdn1:port=xe-0/0/0',
        'hostName':'albu-sdn1',
        'ifName':'xe-0/0/0',
        'ifDescription':'albu-sdn1-&gt;albu-cr1:10ge:ip:show:na',
        'capacity':'10000000000',
        'direction':'in',
        'authRealm':'ESnet-Public'
    }
    metaParams = {
        'supportedEventType':['http://ggf.org/ns/nmwg/characteristic/utilization/2.0',
                                'http://ggf.org/ns/nmwg/tools/snmp/2.0']
    }
    psm = psMessageBuilder('message.5409164', 'SetupDataResponse',
                            messageIdRef='#message1')
                            
    psm.addMetadataBlock('metadata.2885181', subject='subj1307', subjectType='interface',
                        subjectData=responseMeta, params=metaParams, paramid='metaparam1307',
                        eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0')
    psm.addMetaIdRef('metadata.2885181', '#metaIn')
    
    psm.addDataBlock('data.15849525', metadataIdRef='metadata.2885181')
    
    # let's pretend this is some sort of DB query response
    results = [
    ["1358.2", "1254123570"],
    ["1600.1", "1254123600"],
    ["1285.3", "1254123630"]
    # etc etc etc
    ]
    for r in results:
        datum = {'timeType':'unix', 'value':r[0], 'valueUnits':'Bps', 'timeValue':r[1]}
        psm.addDatumToDataBlock('data.15849525', attrs=datum)
    
    print psm.tostring(cleanup=True)
    pass


if __name__ == '__main__':
    makeRequest()
    makeResponse()
    
#####

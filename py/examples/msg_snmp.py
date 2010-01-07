from perfsonar.message import psMessageBuilder

def main():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    
    interfaceDesc = {
        'ifAddress type="ipv4"':'127.0.0.1',
        'hostName':'localhost',
        'ifName':'eth0',
        'ifIndex':'2',
        'direction':'in',
        'capacity':'1000000000',
        'ifDescription':'localhost 1G Ethernet Connection',
        'description':'localhost 1G Ethernet Connection',
        'authRealm':'public'
    }
    
    metaParams = {
        'supportedEventType':['http://ggf.org/ns/nmwg/characteristic/errors/2.0',
                                'http://ggf.org/ns/nmwg/tools/snmp/2.0']
    }
    
    psm.addMetadataBlock('m-in-neterr-1', 
                        subject='s-in-neterr-1', subjectType='interface', 
                        subjectData=interfaceDesc,
                        forceSubjectNS='http://ggf.org/ns/nmwg/characteristic/errors/2.0/',
                        params=metaParams, paramid='p-in-neterr-1',
                        eventType=['http://ggf.org/ns/nmwg/tools/snmp/2.0', 
                                    'http://ggf.org/ns/nmwg/characteristic/errors/2.0']
                        )
                        
    psm.addDataBlock('d-in-netutil-1')
    keyparams = {
        "supportedEventType": ['http://ggf.org/ns/nmwg/tools/snmp/2.0',
                    'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'],
        "type":'rrd',
        "file":'./localhost.rrd',
        "valueUnits":'Bps',
        "dataSource":'ifinoctets'
    }
    
    psm.addKeyToDataBlock('d-in-netutil-1', keyid='k-in-netutil-1', 
                        paramid='pk-in-netutil-1', params=keyparams)
    

    
    print psm.tostring(cleanup=True)
    
    pass
    
if __name__ == '__main__':
    main()

######


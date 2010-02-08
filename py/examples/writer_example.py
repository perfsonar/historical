from perfsonar.message import psMessageBuilder
import logging

# Commented example that shows the various moving parts of the 
# message builder class.

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG,
                        format="%(levelname)s: %(name)s: %(funcName)s : %(message)s")
    # Construct the message - arg1 is the id and arg2 is the message type
    psm = psMessageBuilder('msg4', 'MeasurementArchiveStoreRequest')
    
    # parameters can be added to a variety of elements so if the 
    # second/parentid arg is left undefined, it will add to the
    # main message body
    parms = {
    'authToken':'Internet2',
    'timeValue':'1138699951',
    'timeType':'unix'
    }
    psm.addParameters('msgparam1', params=parms)
    
    # metadata is only added to the main message, so no parent ID is required
    # subject, paramid, params, and eventType are optional args to add these 
    # when the block is created.  If a params dict is passed in, a parameters
    # section will be created.  If the paramid is passed in, that parameter
    # blocked will be given that id.  If a subjectType is included, then 
    # and element of that type will be added to the subject element - and if
    # a subjectData dict is defined, that subject type (ie: interface, etc),
    # will be populated with that data.
    interfaceData = {
    'hostName':'test-hostName',
    # text after the element name of this string="string" format
    # will be parsed into and handled as element attributes
    'ifAddress type="ipv4"':'10.1.2.2',
    'ifName':'test-0',
    'ifDescription':'test description',
    'direction':'in',
    'authRealm':'TestRealm',
    'capacity':'1000BaseT'
    }
    metaParams = {
    "dataSourceStep":'300',
    "dataSourceType":'COUNTER',
    "dataSourceHeartbeat":'1800',
    "dataSourceMinValue":'0',
    "dataSourceMaxValue":'10000000000000'
    }
    psm.addMetadataBlock('meta1', 
                subject='subj1',
                # this can be set to override default "utilization" namespace
                #forceSubjectNS='http://ggf.org/ns/nmwg/characteristic/errors/2.0/',
                subjectType='interface', 
                subjectData=interfaceData,
                params=metaParams, 
                paramid='param1', # can be left out for no id
                eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
                # can also pass in a list for multple event types
                #eventType=['Event 1', 'Event 2']
                )
    
    # add a data block to the message - the first arg is the required
    # id of the data block.  All additional keyword args will be added
    # to the data element as attributes.
    psm.addDataBlock('data1', metadataIdRef='meta1')
    
    # add datum elements - different method as this will most likely get
    # iterated over and because data blocks do not always contain datum 
    # elements.  The first argument is the id attribute of the block we
    # wish to add to.  If the datum element has contents rather than just 
    # attributes, a "content" keyword may be passed in.  
    # ie: <datum>23</datum> rather than simply <datum/>
    data = {
    'value':"12345",
    'timeValue':"1179149601",
    'timeType':"unix",
    'valueUnits':"bps"
    }
    psm.addDatumToDataBlock('data1', attrs=data)
    #psm.addDatumToBlock('data1', attrs=data, content=23)
    
    # The following will generate a key structure for data block.
    # keyparams = {
    # # can pass in a list if there is more than one parameter with 
    # # the same name
    # "supportedEventType": ['http://ggf.org/ns/nmwg/tools/snmp/2.0',
    #                     'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'],
    # "type":'rrd',
    # "file":'./localhost.rrd',
    # "valueUnits":'Bps',
    # "dataSource":'ifinoctets'
    # }
    # psm.addKeyToDataBlock('data1', keyid='k-in-netutil-1', 
    #                         paramid='pk-in-netutil-1', params=keyparams)
    
    print psm.tostring(cleanup=True)
    pass
    
    
########
import logging, re

from lxml import etree, objectify

import perfsonar.namespaces as namespaces

log = logging.getLogger(__name__)

class psMessage(object):
    def __init__(self):
        self.message = None
        
    def findElementByID(self, eid):
        # see if we are hitting the message itself
        if self.message.attrib['id'] == eid:
            return self.message
        # walk the tree otherwise
        for i in self.message.iterdescendants():
            if i.attrib.has_key('id'):
                if i.attrib['id'] == eid:
                    return i
        return None
        
    def tostring(self, cleanup=False):
        if cleanup:
            self.cleanup()
        if self.message != None:
            return etree.tostring(self.message, pretty_print=True)
        else:
            return 'No message defined'
            
    def cleanup(self):
        if self.message != None:
            etree.cleanup_namespaces(self.message)
    
class psMessageBuilder(psMessage):
    def __init__(self, messageId, messageType, **kwargs):
        super(psMessageBuilder, self).__init__()
        self.messageId = messageId
        self.messageType = messageType
        
        self.message = self.createElement('message', self.messageId, 
                                            type=self.messageType, **kwargs)
    
    def createElement(self, elementName, eid, **kwargs):
        messageE = objectify.ElementMaker(annotate=False, 
        namespace = namespaces.elementNameToNS(elementName),
        nsmap=namespaces.nsdict)
        extraAtts = ''
        if kwargs:
            extraAtts = ', '
            for k,v in kwargs.items():
                if k == 'payload':
                    continue
                extraAtts += "%s='%s', " % (k,v)
                
        command = None
        if eid is not None:
            if not kwargs.has_key('payload'):
                command = "messageE.%s(id='%s'%s)" % \
                    (elementName, eid, extraAtts[0:-2])
            else:
                command = "messageE.%s('%s', id='%s'%s)" % \
                    (elementName, kwargs['payload'], eid, extraAtts[0:-2])
        if eid is None:
            if not kwargs.has_key('payload'):
                command = "messageE.%s(%s)" % (elementName, extraAtts[2:-2])
            else:
                command = "messageE.%s('%s', %s)" % \
                    (elementName, kwargs['payload'], extraAtts[2:-2])
                    
        log.debug(command)
        return eval(command)
    
    def addElement(self, elementName, eid, parentid, **kwargs):
        newElement = self.createElement(elementName, eid, **kwargs)
        parent = self.findElementByID(parentid)
        if parent is not None:
            parent.append(newElement)
        else:
            er = 'Did not find element with id = ' + parentid
            log.error(er)
            raise RuntimeError(er)
        # return the new element to the calling method in case 
        # post processing is going on
        return newElement
        
    def splitNameToAttributes(self, name):
        atts = {}
        valSplit = name.split(' ')
        if len(valSplit) == 1:
            return None
        else:
            log.debug('Splitting input: ' +  name)
            for att in valSplit[1:]:
                if not att.split():
                    continue
                attSplit = att.split('="')
                log.debug('Split attributes: ' + attSplit[0] + \
                            ' = ' + attSplit[1][:-1])
                atts[attSplit[0]] = attSplit[1][:-1]
        return atts
        
    def addMetaIdRef(self, eid, value):
        element = self.findElementByID(eid)
        element.set('metadataIdRef', value)
    
    def addParameters(self, eid, parentid=None, params=None):
        if parentid is None:
            parentid = self.messageId
        parms = self.addElement('parameters', eid, parentid)
        if params is not None:
            for k,v in params.items():
                if type(v) != type([]):
                    # add a single parameter
                    parms.append(self.createElement('parameter', None, 
                                                    name=k, payload=v))
                else:
                    for multival in v:
                        # for repeating params like supportedEventType
                        parms.append(self.createElement('parameter', None, 
                                                        name=k, payload=multival))
    
            
    def addMetadataBlock(self, eid, subject=None, forceSubjectNS=None,
                        subjectType=None, subjectData=None,
                        eventType=None, paramid=None, params=None):
        metadata = self.addElement('metadata', eid, self.messageId)
        if subject is not None:
            subject = self.createElement('subject', subject)
            metadata.append(subject)
            # put NS override here so as to leave the usual
            # element code alone
            if forceSubjectNS is not None:
                if not forceSubjectNS.endswith('/'):
                    forceSubjectNS = forceSubjectNS + '/'
                subject.tag = '{%s}subject' % forceSubjectNS
            elif type(eventType) == type('str'):
                if not eventType.endswith('/'):
                    subject.tag = '{%s/}subject' % eventType
                else:
                    subject.tag = '{%s}subject' % eventType
            elif type(eventType) == type([]):
                subNS = None
                for et in eventType:
                    if not et.endswith('/'):
                        et = et + '/'
                    if namespaces.nsToPrefix(et) != 'nmwg':
                        subject.tag = '{%s}subject' % et
                        break
            if subjectType is not None:
                sType = self.createElement(subjectType, None)
                subject.append(sType)
                if subjectData is not None:
                    for k,v in subjectData.items():
                        atts = self.splitNameToAttributes(k)
                        if atts is not None:
                            sType.append(self.createElement(k.split(' ')[0], None, 
                                                payload=v, **atts))
                        else:
                            sType.append(self.createElement(k, None, payload=v))
                        pass
        if params is not None:
            self.addParameters(paramid, metadata.attrib['id'], params)
        if eventType is not None:
            events = []
            if type(eventType) == type('str'):
                events.append(eventType)
            elif type(eventType) == type([]):
                events = eventType
            else:
                pass
                
            for e in events:
                metadata.append(self.createElement('eventType', None, 
                                                    payload=e))
     
    def addDataBlock(self, eid, **kwargs):
        data = self.addElement('data', eid, self.messageId, **kwargs)

    def addDatumToDataBlock(self, eid, attrs=None, content=None):
        datum = None
        if content is None:
            datum = self.addElement('datum', None, eid, **attrs)
        else:
            datum = self.addElement('datum', None, eid, 
                                    payload=content, **attrs)
    
    def addKeyToDataBlock(self, eid, keyid=None, paramid=None, params=None):
        key = self.addElement('key', keyid, eid)
        if paramid is not None:
            self.addParameters(paramid, key.attrib['id'], params)
    
    

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG,
                        format="%(levelname)s: %(funcName)s : %(message)s")
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



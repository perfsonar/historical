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
    pass
    
    
########



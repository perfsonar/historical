import logging, re

from lxml import etree, objectify

import perfsonar.namespaces as namespaces

log = logging.getLogger(__name__)

class psMessage(object):
    def __init__(self):
        self.message = None
        
    def findElementByID(self, eid):
        """
        Searches the message and returns an element based on the
        id parameter.
        """
        # see if we are hitting the message itself
        if self.message.attrib['id'] == eid:
            return self.message
        # walk the tree otherwise
        for i in self.message.iterdescendants():
            if i.attrib.has_key('id'):
                if i.attrib['id'] == eid:
                    return i
        log.warning('Unable to find element id: %s' % eid)
        return None
        
    def findElementByName(self,ele,name):
        """
        Searches an element for a sub-element with a given name.  Used
        to extract sub-section from a complex element.
        """
        for i in ele.iterdescendants():
            elementInfo = self.getElementInformation(i)
            if elementInfo['name'] == name:
                return i
        
    def tostring(self, cleanup=False):
        """
        Returns message as a string.
        """
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
                        eventType=None, paramid=None, params=None, **kwargs):
        metadata = self.addElement('metadata', eid, self.messageId, **kwargs)
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
            parms = self.createElement('parameters', paramid)
            key.append(parms)
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
    

########

class psMessageReader(psMessage):
    def __init__(self,msg=None):
        """
        Ctor - Can be initialized by either an XML string or an etree.Element
        object as is used in the server dispatch library.
        """
        super(psMessageReader, self).__init__()
        
        self.messageId = None
        self.messageIdRef = None
        self.messageType = None
        self.mainMessageElements = {'data':[], 'metadata':[], 'parameters':[]}
        log.debug('%s' % self)
        
        if type(msg) == str:
            self.message = self.initializeMessage(etree.fromstring(msg))
        elif type(msg) == type(etree.Element("foo")):
            self.message = self.initializeMessage(msg)
        else:
            er = 'Bad initialization with type: %s' % type(msg)
            log.error(er)
            raise RuntimeError(er)
            
    def initializeMessage(self,msg):
        """
        Finds the base nmwg:message element - stripping off things like
        SOAP headers - and identifies the ids of the main message elements
        (parameters, data and metadata) for later retrieval.
        """
        messageElement = None

        elementInfo = self.getElementInformation(msg)

        if elementInfo['name'] == 'message' \
            and elementInfo['type']:
            log.debug('Message passed in.')
            messageElement = msg
        else:
            log.debug('Stripping message.')
            for i in msg.iterdescendants():
                eInfo = self.getElementInformation(i)
                if eInfo['name'] == 'message' \
                    and eInfo['type']:
                    messageElement = i
                    break

        elementInfo = self.getElementInformation(messageElement)
        self.messageId = elementInfo['id']
        self.messageType = elementInfo['type']
        
        if messageElement.attrib.has_key('messageIdRef'):
            self.messageIdRef = messageElement.attrib['messageIdRef']

        for i in messageElement.iterdescendants():
            if self.isComment(i):
                continue
            eInfo = self.getElementInformation(i)
            try:
                if ['data', 'metadata', 'parameters'].index(eInfo['name']) > -1 \
                    and eInfo['parenttag'] == 'message':
                    self.mainMessageElements[eInfo['name']].append(eInfo['id'])
            except ValueError:
                pass

        return messageElement
        
    # Internal utility methods
    
    def getElementInformation(self,ele):
        """
        Generates a dict of information about a given element.
        """
        elementInfo = {}
        if ele is None:
            return elementInfo
        elementInfo['name'] = ele.tag.split('}')[1]
        elementInfo['ns'] = ele.tag.split('{')[1][:ele.tag.split('{')[1].find('}')]
        elementInfo['prefix'] = namespaces.nsToPrefix(elementInfo['ns'])
        elementInfo['id'] = None
        elementInfo['type'] = None
        elementInfo['parenttag'] = None
        if ele.attrib.has_key('id'):
            elementInfo['id'] = ele.attrib['id']
        if ele.attrib.has_key('type'):
            elementInfo['type'] = ele.attrib['type']
        if ele.getparent() != None:
            elementInfo['parenttag'] = ele.getparent().tag.split('}')[1]
            
        return elementInfo
        
    def isComment(self,e):
        """
        Utility method to identify and skip comments.
        """
        if type(e) == type(etree.Comment("foo")):
            return True
        return False

    def makeSimpleDictFromElement(self,ele):
        """
        Makes a dict out of the children of the passed in element.
        The key is the name of the element itself.
        """
        params = {}
        if ele == None:
            return params
        for e in ele.iterchildren():
            try:
                eInfo = self.getElementInformation(e)
                if params.has_key(eInfo['name']):
                    if type(params[eInfo['name']]) != type([]):
                        params[eInfo['name']] = [params[eInfo['name']]]
                    params[eInfo['name']].append(e.text)
                else:
                    params[eInfo['name']] = e.text
            except:
                er = 'Unable to get value from child element %s in %s' \
                    % (e, ele)
                log.error(er)
                raise RuntimeError(er)
        return params

    def makeSimpleDictFromElementNameAttr(self,ele):
        """
        Makes a dict out of the children of the passed in element.
        The key is derived from the name ATTRIBUTE of the element.
        """
        params = {}
        if ele == None:
            return params
        for e in ele.iterchildren():
            try:
                # value can be in an attribute 'value', or the text
                # child of the element
                value = e.get("value", e.text)
                if params.has_key(e.attrib['name']):
                    if type(params[e.attrib['name']]) != type([]):
                        params[e.attrib['name']] = [params[e.attrib['name']]]
                    params[e.attrib['name']].append(value)
                else:
                    params[e.attrib['name']] = value
            except:
                er = 'Unable to get value from child element %s in %s' \
                    % (e, ele)
                log.error(er)
                raise RuntimeError(er)
        return params
        
    def makeDictFromKeyStructure(self,e):
        key = {}
        ke = self.findElementByName(e, 'key')
        if ke == None:
            return key
        eInfo = self.getElementInformation(ke)
        key['keyid'] = eInfo['id']
        pe = self.findElementByName(ke, 'parameters')
        peInfo = self.getElementInformation(pe)
        if peInfo:
            key['parametersid'] = peInfo['id']
        for k,v in self.makeSimpleDictFromElementNameAttr(pe).items():
            key[k] = v
        return key
        
    # Pull information about the message and its contents.
            
    def getMessageId(self):
        """
        Returns message id.
        """
        return self.messageId
        
    def getMessageIdRef(self):
        """
        Returns message id ref if there is one.
        """
        return self.messageIdRef
        
    def getMessageType(self):
        """
        Returns message type - ie: MeasurementArchiveStoreRequest, etc.
        """
        return self.messageType
        
    def getDataBlockIds(self):
        """
        Returns a list of data block ids.
        """
        return self.mainMessageElements['data']
        
    def getParamBlockIds(self):
        """
        Returns a list of message-level parameter block ids.
        """
        return self.mainMessageElements['parameters']
        
    def getMetadataBlockIds(self):
        """
        Returns a list of metadata section ids.
        """
        return self.mainMessageElements['metadata']
        
    # Methods handling message-level parameter blocks
        
    def getParameters(self, eid):
        """
        Returns a perfsonar.Parameters subclass object to give
        attribute-style access to a message level named
        parameter block.
        """
        return Parameters(self.findElementByID(eid), eid)
        
    def fetchMessageParams(self,eid):
        """
        Returns a message-level parameter block as a dict.
        """
        pEle = self.findElementByID(eid)
        elementInfo = self.getElementInformation(pEle)
        if elementInfo['name'] != 'parameters' \
            and elementInfo['parenttag'] != 'message':
            log.error('id %s is not a message level parameter block' % eid)
        #print objectify.dump(pEle)
        
        return self.makeSimpleDictFromElementNameAttr(pEle)
        
    # Methods handling metadata blocks and the contents of said.
        
    def getMetadata(self,eid):
        """
        Returns a perfsonar.Metadata subclass object to give
        attribute-style access to a single named metadata block.
        """
        meta_elt = self.findElementByID(eid)
        return Metadata(meta_elt, eid)
        
    def fetchMetadataAttributes(self,eid):
        """
        Returns a dict of any attributes in the metadata element
        itself.
        """
        mdEle = self.findElementByID(eid)
        return mdEle.attrib
        
    def fetchMetadataSubject(self,eid):
        """
        Returns subject information (id, ns and prefix) from a
        named metadata section as a dict.
        """
        sInfo = {}
        mdEle = self.findElementByID(eid)
        s = self.findElementByName(mdEle, 'subject')
        if s == None:
            return sInfo
        elementInfo = self.getElementInformation(s)
        sInfo['id'] = elementInfo['id']
        sInfo['ns'] = elementInfo['ns']
        sInfo['prefix'] = elementInfo['prefix']
        for k,v in s.attrib.items():
            if not sInfo.has_key(k):
                sInfo[k] = v
        return sInfo
        
    def fetchMetadataInterface(self,eid):
        """
        Returns interface information from a named metadata section
        as a dict.
        """
        mdEle = self.findElementByID(eid)
        interface = self.findElementByName(mdEle, 'interface')
        return self.makeSimpleDictFromElement(interface)
        
    def fetchMetadataParams(self,eid):
        """
        Returns the parameter block from a named metadata section
        as a dict.
        """
        parms = {}
        mdEle = self.findElementByID(eid)
        pe = self.findElementByName(mdEle, 'parameters')
        if pe == None:
            return parms
        eInfo = self.getElementInformation(pe)
        if eInfo['parenttag'] != 'metadata':
            return parms
        parms = self.makeSimpleDictFromElementNameAttr(pe)
        parms['id'] = eInfo['id']
        return parms

    def fetchMetadataEventType(self, eid):
        """
        Returns the event type from a named metadata section.
        """
        mdEle = self.findElementByID(eid)
        mDict = self.makeSimpleDictFromElement(mdEle)
        if mDict.has_key('eventType'):
            return mDict['eventType']
        else:
            return None
        
    def fetchMetadataKey(self,eid):
        """
        Return a dict of information from a key struction from
        a named metadata block.
        """
        mdEle = self.findElementByID(eid)
        key = self.makeDictFromKeyStructure(mdEle)
        # post process here as per data structure if need be
        return key
        
    # Methods for pulling information from data blocks.
        
    def getData(self,eid):
        """
        Returns a perfsonar.Data subclass object to give
        attribute-style access to a single named metadata block.
        """
        return Data(self.findElementByID(eid), eid)
        
    def fetchDataAttributes(self,eid):
        """
        Returns a dict of any attributes in the data element.
        """
        dEle = self.findElementByID(eid)
        return dEle.attrib
        
    def fetchDataKey(self,eid):
        """
        Return a dict of information from a key struction from
        a named data block.
        """
        dEle = self.findElementByID(eid)
        key = self.makeDictFromKeyStructure(dEle)
        # post process here as per data structure if need be
        return key
        
    def fetchDataDatumValues(self,eid):
        """
        Returns a list of dicts of the datum values from a named
        data block.  Meant for handling output like this:
        
        <nmwg:datum value="12345" timeValue="1138617912" timeType="unix"/>
        
        Each dict contains the key/value pairs of the attributes.
        """
        datumList = []
        dEle = self.findElementByID(eid)
        for i in dEle.iterchildren():
            eInfo = self.getElementInformation(i)
            if eInfo['name'] == 'datum':
                datumList.append(i.attrib)
        return datumList


        
class StructureBase(psMessageReader):
    """
    Common superclass for all the attribute access style 
    section classes.  Subclasses psMessageReader.
    """
    def __init__(self,msg,eid):
        self.message = msg
        self.eid = eid
        log.debug('%s' % self)
    @property
    def id(self):
        return self.eid


class Parameters(StructureBase):
    """
    A subclass of StructureBase to give attribute-style
    access to a named Parameters block:

    p = reader.getParameters(i)
    print p.params
    """
    @property
    def params(self):
        return self.fetchMessageParams(self.eid)
        
class Metadata(StructureBase):
    """
    A subclass of StructureBase to give attribute-style
    access to a named metadata block:
    
    m = reader.getMetadata(i)
    print m.subject
    print m.interface
    print m.params
    print m.eventType
    """
    @property
    def attribs(self):
        return self.fetchMetadataAttributes(self.eid)
    @property
    def subject(self):
        return self.fetchMetadataSubject(self.eid)
    @property
    def interface(self):
        return self.fetchMetadataInterface(self.eid)
    @property
    def params(self):
        return self.fetchMetadataParams(self.eid)
    @property
    def eventType(self):
        return self.fetchMetadataEventType(self.eid)
    @property
    def key(self):
        return self.fetchMetadataKey(self.eid)
    
class Data(StructureBase):
    """
    Subclass of StructureBase to give attribute-style
    access to the contents of a named data block.
    """
    @property
    def attribs(self):
        return self.fetchDataAttributes(self.eid)
    @property
    def key(self):
        return self.fetchDataKey(self.eid)
    @property
    def datumValues(self):
        return self.fetchDataDatumValues(self.eid)

if __name__ == '__main__':
    pass
    
    
########



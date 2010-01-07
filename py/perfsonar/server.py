"""Basic perfSONAR server.

The psMessageFix class is in places of the standard soaplib.soap.Message class
and implements the perfSONAR "unwrapped" messages.
"""
import logging

import soaplib.soap
from soaplib.xml import NamespaceLookup, ElementTree, create_xml_element, ns
from soaplib.wsgi_soap import SimpleWSGISoapApp
from soaplib.service import soapmethod
from soaplib.serializers.primitive import Any

import warnings
# shut up an annoying message from soaplib
warnings.filterwarnings("ignore", category=FutureWarning, append=1)

log = logging.getLogger(__name__)

################

class psMessageFix(soaplib.soap.Message):
    """Implement perfSONAR "unwrapped" messages.
    
    Soaplib expects "wrapped" doc/lit messages but the bulk of the ps messages
    are not wrapped.  This modifies one of the soaplib classes and adds in 
    hooks to deal with unwrapped nmwg:messages.

    This class is monkeypatched as a replacement for the standard
    soaplib.soap.Message.  """

    def from_xml(self,element):
        results = []        
        try:
            children = element.getchildren()
        except:
            return []
        
        def findall(name):
            # inner method for finding child node
            nodes = []
            for c in children:
                if c.tag.split('}')[-1] == name:
                    nodes.append(c)
            return nodes
                
        for name, serializer in self.params:
            if serializer.__name__ == 'psUnwrappedMessage':
                log.debug('messageFix.from_xml(): handling psUnwrappedMessage')
                results.append(serializer.from_xml(element))
                break
            childnodes = findall(name)
            if len(childnodes) == 0:
                results.append(None)
            else:
                results.append(serializer.from_xml(*childnodes))
        return results
        
    def to_xml(self,*data):
        if self.params[0][1].__name__ == 'psUnwrappedMessage':
            log.debug('messageFix.to_xml(): handling psUnwrappedMessage')
            return data[0]

        if len(self.params):
            if len(data) != len(self.params):
                raise Exception("Parameter number mismatch expected [%s] got [%s]"%(len(self.params),len(data)))

        nsmap = NamespaceLookup(self.ns)
        element = create_xml_element(self.name, nsmap, self.ns)

        for i in range(0,len(self.params)):
            name, serializer = self.params[i]
            d = data[i]
            e = serializer.to_xml(d, name, nsmap)
            if type(e) in (list,tuple):
                elist = e
                for e in elist:
                    element.append(e)
            elif e == None:
                pass
            else:
                element.append(e)    

        ElementTree.cleanup_namespaces(element)    
        return element
        
# Swap in the replacement class before the other imports
soaplib.soap.__dict__['Message'] = psMessageFix  

        
class psUnwrappedMessage(Any):
    """perfSONAR "unwrapped" serializer/deserializer.
    
    This classes subclasses one of the soaplib serializers and makes some
    modifications to handle unwrapped messages.
    
    The psService class that will handle most of the transactions on its own
    already uses the this serializer.  But if someone writes their own wrapped
    methods, they MUST use the psWrappedMessage serializer as their in/out
    types.
    """
    @classmethod
    def from_xml(cls,element):
        log.debug('psUnwrappedMessage.from_xml()')
        if element.tag == '{http://ggf.org/ns/nmwg/base/2.0/}message':
            return element
        else:
            er = 'Did not recieve a nmwg:message: ' + element.tag
            log.error(er)
            raise RuntimeError(er)
            
class psWrappedMessage(Any):
    """perfSONAR "wrapped" serializer/deserializer.

    This classes subclasses one of the soaplib serializers and makes some
    modifications to handle wrapped messages.
    
    The psService class that will handle most of the transactions on its own
    already uses the psUnwrappedMessage serializer.  But if someone writes
    their own wrapped methods, they MUST use the psWrappedMessage serializer
    as their in/out types."""

    @classmethod
    def from_xml(cls, element):
        log.debug('psWrappedMessage.from_xml()')
        return element
        
    @classmethod
    def to_xml(cls,value,name='retval',nsmap=ns):
        log.debug('psWrappedMessage.to_xml()')
        if type(value) == str:
            value = ElementTree.fromstring(value)
        return value
        

class psService(SimpleWSGISoapApp):    
    """Base class for a perfSONAR service.
    
    This class provides the base functionality for handling the usual
    unwrapped nmwg:message requests.  The dispatchmap dict will be
    populated in a subclass instance and it will dispatch to the apropos
    method based on the contents of the "type" attribute in the message
    element.  It will hand the incoming nmwg:message to the dispatch
    method as an lxml.etree object and will expect that a new lxml.etree
    object containing the return nmwg:message will be handed back - that
    is what will be returned to the client."""
    dispatchmap = {}
    @soapmethod(psUnwrappedMessage,_returns=psUnwrappedMessage)
    def message(self,message):
        log.debug('Unwrapped input message:\n\n' + ElementTree.tostring(message))
        log.debug('Message type: ' + message.attrib['type'])
        
        dispatchMethod = None
        if self.dispatchmap.has_key(message.attrib['type']):
            try:
                dispatchMethod = getattr(self, self.dispatchmap[message.attrib['type']])
            except AttributeError:
                er = 'No class/dispatch method named: ' + \
                    self.dispatchmap[message.attrib['type']]
                log.fatal(er)
                raise RuntimeError(er)
        else:
            er = 'No entry in dispatch map for nmwg:message type: ' + message.attrib['type']
            log.fatal(er)
            raise RuntimeError(er)
            
        log.debug('Calling: ' + dispatchMethod.__name__)
        return dispatchMethod(message)

def serveWithCherryPy(host, port, serviceObject):
    """Helper method to start service in a CherryPy server. 
    
    Could ostensibly be used in any wsgi-compliant server container."""

    try:
        from cherrypy._cpwsgiserver import CherryPyWSGIServer
        server = CherryPyWSGIServer((host,port),serviceObject)
        server.start()
    except ImportError:
        print 'You do not seem to have CherryPy installed.'
    except KeyboardInterrupt:
        server.stop()
        print "\nDone"

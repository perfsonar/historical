<?xml version="1.0"?>
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0"
               xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/"
               xmlns:nmtopo="http://ggf.org/ns/nmwg/topology/base/3.0/"
	       xmlns:nmtopol2="http://ggf.org/ns/nmwg/topology/l2/3.0/"
	       xmlns:nmtopol3="http://ggf.org/ns/nmwg/topology/l3/3.0/"
	       xmlns:nmtopol4="http://ggf.org/ns/nmwg/topology/l4/3.0/"
	       exclude-result-prefixes="nmwg nmtopo nmtopol2 nmtopol3 nmtopol4">        
  <xsl:output method="text" omit-xml-declaration="yes" indent="no" />

  <!--
    Shape mappings
    ==============

    invhouse = network
    ellipse = node
    hexagon = interface
    diamond = link
    triangle = path
    endpoint = trapezium
  -->

  <!-- ================================================ -->
  <!--                   Main Section                   -->
  <!-- ================================================ -->	
  
  <xsl:template match="/" name="main">  
    <xsl:for-each select="/nmwg:message/nmwg:metadata">
      digraph g {	
        <xsl:call-template name="base_network" />
        <xsl:call-template name="l3_network" />
        <xsl:call-template name="l2_network" />    
        <xsl:call-template name="base_path" />
        <xsl:call-template name="l2_path" />
        <xsl:call-template name="l3_path" />  
        <xsl:call-template name="base_link" />
        <xsl:call-template name="l2_link" />
        <xsl:call-template name="l3_link" />
        <xsl:call-template name="base_node" /> 
        <xsl:call-template name="base_interface" />
        <xsl:call-template name="l2_interface" />
        <xsl:call-template name="l3_interface" />          
      }  
    </xsl:for-each>
  </xsl:template>



  <!-- =================================================== -->
  <!--                   Network Section                   -->  
  <!-- =================================================== -->  
  
  <!--
  :Base Network Extras:
  nmtopo:type
  -->
  <xsl:template name="base_network">
    <xsl:for-each select="./nmtopo:network">
      <xsl:if test="./@networkIdRef">
        "<xsl:value-of select="./@networkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>       
      subgraph cluster_base_network_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=invhouse]
        <xsl:if test="./nmtopo:name">
          <xsl:value-of select="./@id" /> [shape=invhouse,label="<xsl:value-of select="./nmtopo:name" />"]
	      </xsl:if>
	      <xsl:call-template name="base_interface" />	
	      <xsl:call-template name="l3_interface" />
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="base_link" />
	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />		
	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>

  <!--
  :L3 Network Extras:
  nmtopol3:type
  nmtopol3:subnet
  nmtopol3:netmask
  nmtopol3:asn 
  -->
  <xsl:template name="l3_network">
    <xsl:for-each select="./nmtopol3:network">
      <xsl:if test="./@networkIdRef">
        "<xsl:value-of select="./@networkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>       
      subgraph cluster_l3_network_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=invhouse]	
        <xsl:if test="./nmtopol3:name">
          <xsl:value-of select="./@id" /> [shape=invhouse,label="<xsl:value-of select="./nmtopol3:name" />"]	
	      </xsl:if>
	      <xsl:call-template name="l3_interface" />
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />		
	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>

  <!--
  :L2 Network Extras:
  nmtopol2:type
  nmtopol2:vlan
  -->  
  <xsl:template name="l2_network">
    <xsl:for-each select="./nmtopol2:network">
      <xsl:if test="./@networkIdRef">
        "<xsl:value-of select="./@networkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>       
      subgraph cluster_l2_network_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=invhouse]	
        <xsl:if test="./nmtopol2:name">
          <xsl:value-of select="./@id" /> [shape=invhouse,label="<xsl:value-of select="./nmtopol2:name" />"]	
	      </xsl:if>      
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="l2_link" />		
	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>  


  <!-- ================================================ -->
  <!--                   Link Section                   -->
  <!-- ================================================ -->

  <!--
  :Base Link Extras:
  nmtopo:index
  nmtopo:type
  nmtopo:globalName  
  -->  
  <xsl:template name="base_link">
    <xsl:for-each select="./nmtopo:link">
      <xsl:if test="./@linkIdRef">
        "<xsl:value-of select="./@linkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>    
      subgraph cluster_base_link_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=diamond]	
        <xsl:if test="./nmtopo:name">
          <xsl:value-of select="./@id" /> [shape=diamond,label="<xsl:value-of select="./nmtopo:name" />"]	
	      </xsl:if>      
	      <xsl:call-template name="base_interface" />	
	      <xsl:call-template name="l3_interface" />
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="base_link" />
	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />		
 	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>


  <!--
  :L3 Link Extras:
  nmtopol3:index
  nmtopol3:type
  nmtopol3:globalName  
  -->
  <xsl:template name="l3_link">
    <xsl:for-each select="./nmtopol3:link">
      <xsl:if test="./@linkIdRef">
        "<xsl:value-of select="./@linkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>    
      subgraph cluster_base_link_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=diamond]	
        <xsl:if test="./nmtopol3:name">
          <xsl:value-of select="./@id" /> [shape=diamond,label="<xsl:value-of select="./nmtopol3:name" />"]	
	      </xsl:if>       	
	      <xsl:call-template name="l3_interface" />
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />		
	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>

  <!--
  :L2 Link Extras:
  nmtopol2:index
  nmtopol2:type
  nmtopol2:globalName  
  -->  
  <xsl:template name="l2_link">
    <xsl:for-each select="./nmtopol2:link">
      <xsl:if test="./@linkIdRef">
        "<xsl:value-of select="./@linkIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>    
      subgraph cluster_base_link_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=diamond]	
        <xsl:if test="./nmtopol2:name">
          <xsl:value-of select="./@id" /> [shape=diamond,label="<xsl:value-of select="./nmtopol2:name" />"]	
	      </xsl:if> 
	      <xsl:call-template name="l2_interface" />		
	      <xsl:call-template name="l2_link" />		
	      <xsl:call-template name="base_node" />
      }
    </xsl:for-each>
  </xsl:template>
  
      
  <!-- ================================================ -->
  <!--                   Path Section                   -->
  <!-- ================================================ -->
        
  <xsl:template name="base_path">
    <xsl:for-each select="./nmtopo:path">
      <xsl:if test="./@pathIdRef">
        "<xsl:value-of select="./@pathIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>
      subgraph cluster_base_path_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=triangle]
	      <xsl:call-template name="base_link" />
	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />	
      }
    </xsl:for-each>
  </xsl:template>      

  <xsl:template name="l3_path">
    <xsl:for-each select="./nmtopol3:path">
      <xsl:if test="./@pathIdRef">
        "<xsl:value-of select="./@pathIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>
      subgraph cluster_l3_path_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=triangle]
 	      <xsl:call-template name="l3_link" />
	      <xsl:call-template name="l2_link" />	
      }
    </xsl:for-each>
  </xsl:template>     
  
  <xsl:template name="l2_path">
    <xsl:for-each select="./nmtopol2:path">
      <xsl:if test="./@pathIdRef">
        "<xsl:value-of select="./@pathIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>
      subgraph cluster_l2_path_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=triangle]
	      <xsl:call-template name="l2_link" />	
      }
    </xsl:for-each>
  </xsl:template>      
  
 
  <!-- ================================================ -->
  <!--                   Node Section                   -->
  <!-- ================================================ -->

  <!--
  :Base Node Extras:
  nmtopo:role
  nmtopo:type
  nmtopo:hostName
  nmtopo:description
  nmtopo:cpu
  nmtopo:operSys
  nmtopo:location
  nmtopo:country
  nmtopo:city
  nmtopo:latitude
  nmtopo:longitude
  nmtopo:institution
  -->        
  <xsl:template name="base_node">
    <xsl:for-each select="./nmtopo:node">
      <xsl:if test="./@nodeIdRef">
        "<xsl:value-of select="./@nodeIdRef" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if>    
      <xsl:if test="../@id">
        "<xsl:value-of select="../@id" />" -> "<xsl:value-of select="./@id" />";
      </xsl:if> 
      subgraph cluster_base_node_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=ellipse]	
        <xsl:if test="./nmtopo:name">
          <xsl:value-of select="./@id" /> [shape=ellipse,label="<xsl:value-of select="./nmtopo:name" />"]	
	      </xsl:if>       
	      <xsl:call-template name="base_interface" />	
	      <xsl:call-template name="l3_interface" />
	      <xsl:call-template name="l2_interface" />	
      }
    </xsl:for-each>
  </xsl:template>



  <!-- ===================================================== -->
  <!--                   Interface Section                   -->
  <!-- ===================================================== -->
  
  <!--
  :Base Interface Extras:
  nmtopo:type
  nmtopo:hostName
  nmtopo:ifName
  nmtopo:ifDescription
  nmtopo:ifIndex
  nmtopo:capacity
  -->  
  <xsl:template name="base_interface">
    <xsl:for-each select="./nmtopo:interface">
      subgraph cluster_base_interface_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=hexagon]	
        <xsl:if test="./nmtopo:name">
          <xsl:value-of select="./@id" /> [shape=hexagon,label="<xsl:value-of select="./nmtopo:name" />"]	
	      </xsl:if>             
        "<xsl:value-of select="../@id" />" -> "<xsl:value-of select="./@id" />";
      }
    </xsl:for-each>    
  </xsl:template>

  <!--
  :L3 Interface Extras:
  nmtopol3:ipAddress
  nmtopol3:netmask
  nmtopol3:ifName
  nmtopol3:ifDescription
  nmtopol3:ifAddress
  nmtopol3:ifIndex
  nmtopol3:type
  nmtopol3:capacity
  -->  
  <xsl:template name="l3_interface">
    <xsl:for-each select="./nmtopol3:interface">
      subgraph cluster_l3_interface_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=hexagon]	
        <xsl:if test="./nmtopol3:ifName">
          <xsl:value-of select="./@id" /> [shape=hexagon,label="<xsl:value-of select="./nmtopol3:ifName" />"]	
	      </xsl:if>        
        "<xsl:value-of select="../@id" />" -> "<xsl:value-of select="./@id" />";
      }
    </xsl:for-each>    
  </xsl:template>  

  <!--
  :L2 Interface Extras:
  nmtopol2:type
  nmtopol2:address
  nmtopol2:name
  nmtopol2:description
  nmtopol2:ifHostName
  nmtopol2:ifIndex
  nmtopol2:capacity
  -->    
  <xsl:template name="l2_interface">
    <xsl:for-each select="./nmtopol2:interface">
      subgraph cluster_l2_interface_<xsl:value-of select="./@id" /> {
        <xsl:value-of select="./@id" /> [shape=hexagon]	
        <xsl:if test="./nmtopol2:name">
          <xsl:value-of select="./@id" /> [shape=hexagon,label="<xsl:value-of select="./nmtopol2:name" />"]	
	      </xsl:if>        
        "<xsl:value-of select="../@id" />" -> "<xsl:value-of select="./@id" />";
      }
    </xsl:for-each>    
  </xsl:template>  

</xsl:transform>

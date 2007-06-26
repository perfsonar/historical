create table nodes (id VARCHAR(255), name VARCHAR(255), country VARCHAR(255), city VARCHAR(255), institution VARCHAR(255), latitude FLOAT, longitude FLOAT);
create table links (id VARCHAR(255), name VARCHAR(255), globalName VARCHAR(255), type VARCHAR(255));
create table link_nodes (link_id VARCHAR(255), node_id VARCHAR(255), role VARCHAR(255), link_index INTEGER);

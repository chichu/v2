create table raw_data(      
        site varchar(255) NOT NULL,
        uid  varchar(255) NULL,
        author varchar(255) NULL,
        channel varchar(255) NULL,
        blogurl varchar(255) NULL,
        blogt  varchar(255) NULL,
        date DATE NULL,
        time TIME NULL,      
        url  varchar(255) NULL,
        keyword varchar(255) NULL,
        title  varchar(255) NULL,
        article TEXT NULL
);
create index site_index on raw_data(site);
create index date_index on raw_data(date);


use enron;

/* Fix date */
alter table messages rename messages_without_dates;
alter table messages_without_dates drop column messagedt;
create table messages_with_dates as select messages_without_dates.*, str_to_date(replace(replace(headers.headervalue, " -0800 (PST)",'')," -0700 (PDT)",""), '%a, %d %b %Y %H:%i:%s') as messagedt from messages_without_dates LEFT JOIN headers on (messages_without_dates.messageid = headers.messageid and headers.headername = 'Date');


alter table messages_with_dates rename messages;
create index messages_messageid on messages(messageid);
create index messages_sender on messages(senderid);
create index messages_subject on messages(subject);
create index messages_subject_sender on messages(subject, senderid);


/* Add is_response column */
alter table messages add column is_response boolean;
update messages set is_response = false;
update messages set is_response = true where lower(subject) like 're:%%';


/* Add re_subject column */
alter table messages add column re_subject varchar(255);
update messages set re_subject=concat("re: ", lower(subject));
update messages set subject=replace(lower(subject), 're: ','');

/* Create indexes on messages */
create index re_subject_index on messages(re_subject);
create index subject_index on messages(subject);
create index subject_sender_index on messages(subject, senderid);
create index subject_sender_index_date on messages(subject, senderid, messagedt);
create index re_subject_sender_index on messages(re_subject, senderid);

/* Replies */
-- select a.subject, a.senderid as senderid, a.messagedt, a_recipients.personid as recipientid, b.subject as reply_subject, b.senderid as reply_senderid, b.messagedt as reply_messagedt 
--     from messages a
--     JOIN recipients a_recipients using (messageid)
--     join messages b
--     on (
--         b.senderid = a_recipients.personid 
--         AND (
--             b.subject = a.re_subject
--             or
--             b.subject = a.subject
--         ) and b.messagedt >= a.messagedt
--     )
--     where trim(a.subject != "")
--     and b.messagedt > a.messagedt
--     limit 100;

/* Recipient Count */
drop table if exists recipient_counts;
create table recipient_counts as select a.messageid, count(*)  as recipient_count, group_concat(personid) as recipient_list
    from messages a
    JOIN recipients using (messageid)
    group by a.messageid;

create index recipient_counts_messageid on recipient_counts(messageid);


/* Reply Ratio */
drop table if exists reply_ratios;
create table reply_ratios as 
    select a.subject, a.messageid, a.messagedt, a.senderid, recipient_count, 
        count(distinct b.senderid) as replier_count, 
        count(distinct b.senderid)/recipient_count as replier_ratio
        from messages a
        JOIN recipient_counts using (messageid)
        JOIN recipients a_recipients using (messageid)
        LEFT JOIN messages b
        on (
            b.senderid = a_recipients.personid 
            and b.messagedt >= a.messagedt
            and b.subject = a.subject
        )
        where trim(a.subject) != ''
        and trim(lcase(a.subject)) != 're:'
        and trim(a.subject) != 'apb checkout'
        group by a.messageid;



-- select bucket, count(*) from reply_ratios group by bucket;

drop table if exists actionability;
create table actionability as 
    SELECT case when replier_ratio > .1 then "ACTIONABLE" 
    else "NOT" END as actionability,
    messageid,
    recipient_count,
    replier_count,
    replier_ratio,
    subject, 
    replace(replace(replace(trim(body),"\n"," "),"\t"," "),"\r"," ") as body,
    senderid,
    crc32(concat(messageid,subject))%4 as bucket
    FROM reply_ratios
    JOIN bodies using (messageid)
    order by replier_ratio desc;


select actionability, subject, body, senderid, recipient_count, replier_count, replier_ratio
from actionability
where bucket = 3
order by crc32(concat(messageid,subject))
INTO OUTFILE '/tmp/actionable-emails.train'
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n';

select actionability, subject, body, senderid, recipient_count, replier_count, replier_ratio
from actionability
where bucket = 2
order by crc32(concat(messageid,subject))
INTO OUTFILE '/tmp/actionable-emails.test'
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n';

select actionability, count(*) from actionability group by actionability;

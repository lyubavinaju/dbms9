create table Flights
(
    FlightId   integer primary key,
    FlightTime timestamp not null,
    PlaneId    integer   not null
);

create table Seats
(
    PlaneId integer    not null,
    SeatNo  varchar(4) not null,
    primary key (PlaneId, SeatNo)
);

create table Users
(
    UserId integer primary key,
    Pass   varchar(34) not null
);

create table Bought
(
    FlightId integer    not null,
    SeatNo   varchar(4) not null,
    primary key (FlightId, SeatNo),
    foreign key (FlightId) references Flights (FlightId)
);

create table Reserved
(
    FlightId integer    not null,
    UserId   integer    not null,
    SeatNo   varchar(4) not null,
    EndTime  timestamp  not null,
    primary key (FlightId, SeatNo),
    foreign key (FlightId) references Flights (FlightId),
    foreign key (UserId) references Users (UserId)
);



insert into Users (UserId, Pass)
VALUES (1, crypt('pass1', gen_salt('md5'))),
       (2, crypt('pass2', gen_salt('md5'))),
       (3, crypt('pass3', gen_salt('md5')));

insert into Seats (PlaneId, SeatNo)
VALUES (10, '100A'),
       (10, '101A'),
       (10, '1A'),
       (10, '102A'),
       (20, '1A'),
       (20, '200A'),
       (20, '201A'),
       (20, '202A'),
       (20, '206A'),
       (20, '208A'),
       (20, '218A'),
       (30, '300A');

insert into Flights (FlightId, FlightTime, PlaneId)
VALUES (100, make_date(2021, 12, 12), 30),
       (200, make_date(2021, 12, 12), 10),
       (300, make_date(2021, 12, 12), 20),
       (400, now() - interval '1 day', 20),
       (500, now() + interval '1 day', 20);

insert into Bought (FlightId, SeatNo)
VALUES (200, '101A'),
       (300, '218A');

insert into Reserved (FlightId, UserId, SeatNo, EndTime)
VALUES (300, 3, '202A', now()),
       (100, 1, '300A', now()),
       (300, 1, '201A', now() + interval '1 day'),
       (300, 1, '208A', now() + interval '1 day');



create function userExists(IN uid integer, IN pwd varchar(34))
    returns boolean
    language plpgsql as
$$
begin
    return exists(select u.UserId from Users u where u.UserId = uid and u.pass = crypt(pwd, u.pass));
end;
$$;

--check that flight is not outdated and find planeId
create procedure flightIsAvailable(in fid integer, inout pid integer, inout res boolean)
    language plpgsql as
$$
declare
    ftime timestamp;
begin
    select f.PlaneId, f.FlightTime
    into pid, ftime
    from Flights f
    where f.FlightId = fid;
    res
        = (pId is not null and fTime >= now());
end;
$$;

--check that plane has given seat
create function seatExists(in pid integer, in sno varchar(4)) returns boolean
    language plpgsql as
$$
begin
    return exists(select * from Seats s where s.PlaneId = pid and s.SeatNo = sno);
end;
$$;

create function seatIsBought(in fid integer, in sno varchar(4))
    returns boolean
    language plpgsql as
$$
begin
    return exists(select * from Bought b where b.FlightId = fid and b.SeatNo = sno);
end;
$$;

create procedure seatIsReserved(in fid integer, in sno varchar(4), inout uid integer, inout res boolean)
    language plpgsql as
$$
declare
    resEndTime timestamp;
begin
    select r.EndTime, r.UserId
    into resEndTime, uid
    from Reserved r
    where r.FlightId = fid
      and r.SeatNo = sno;
    if
        resEndTime is not null then
        if resEndTime >= now() then
            res = true;
        else
            delete
            from Reserved r
            where r.FlightId = fid
              and r.SeatNo = sno;
            res
                = false;
        end if;
    else
        res = false;
    end if;
end;
$$;


create function flightStatHelper(in uid integer, in pwd varchar(4))
    returns table
            (
                FlightId integer,
                fs       integer,
                rs       bigint,
                rsByUser bigint,
                bs       bigint
            )
    language plpgsql
as
$$
begin
    if not userExists(uid, pwd) then
        return query
            select 0, 0, cast(0 as bigint), cast(0 as bigint) limit 0;
    else
        return query select f.FlightId,
                            coalesce(array_length(FreeSeats(f.FlightId), 1), 0),
                            (select count(r.SeatNo) from Reserved r where r.FlightId = f.FlightId and r.EndTime >= now()),
                            (select count(r.SeatNo)
                             from Reserved r
                             where r.FlightId = f.FlightId
                               and r.EndTime >= now()
                               and r.UserId = uid),
                            (select count(b.SeatNo) from Bought b where b.FlightId = f.FlightId)
                     from Flights f
                     where f.FlightTime >= now();
    end if;
end;
$$;



-- 1. FreeSeats(FlightId)
create function FreeSeats(in fid integer) returns varchar(4)[]
    language plpgsql
as
$$
declare
    fAvailable boolean;
    pid        integer;
begin
    call flightIsAvailable(fid, pid, fAvailable);

    if not fAvailable then
        return array [] :: varchar(4)[];
    end if;
    return array(select s.SeatNo
                 from Seats s
                 where s.PlaneId = pid
                     except
                 select r.SeatNo
                 from Reserved r
                 where r.EndTime >= now()
                   and r.FlightId = fid except
                 select b.SeatNo
                 from Bought b
                 where b.FlightId = fid);
end
$$;

-- 2. Reserve(UserId, Pass, FlightId, SeatNo)
create function Reserve(in uid integer,
                        in pwd varchar(34),
                        in fid integer,
                        in sno varchar(4))
    returns boolean
    language plpgsql as
$$
declare
    pid            integer;
    fAvailable     boolean;
    seatIsReserved boolean;
    reservedUid    integer;
begin
    if not userExists(uid, pwd) then return false; end if;

    call flightIsAvailable(fid, pid, fAvailable);
    if not fAvailable then
        return false;
    end if;

    if not seatExists(pid, sno) then
        return false;
    end if;

    if seatIsBought(fid, sno) then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if seatIsReserved then
        return false;
    end if;

    insert into Reserved (FlightId, UserId, SeatNo, EndTime)
    VALUES (fid, uid, sno, now() + interval '3 days');
    return true;

end
$$;

-- 3. ExtendReservation(UserId, Pass, FlightId, SeatNo)
create function ExtendReservation(in uid integer, in pwd varchar(34), in fid integer, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    pid            integer;
    fAvailable     boolean;
    seatIsReserved boolean;
    reservedUid    integer;
begin
    if not userExists(uid, pwd) then return false; end if;

    call flightIsAvailable(fid, pid, fAvailable);
    if not fAvailable then
        return false;
    end if;

    if not seatExists(pId, sno) then
        return false;
    end if;

    if seatIsBought(fid, sno) then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if not seatIsReserved or reservedUid != uid then
        return false;
    end if;

    update Reserved
    set EndTime = now() + interval '3 days'
    where FlightId = fid
      and SeatNo = sno;
    return true;
end;
$$;

-- 4. BuyFree(FlightId, SeatNo)
create function BuyFree(in fid integer, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    pid            integer;
    fAvailable     boolean;
    seatIsReserved boolean;
    reservedUid    integer;
begin
    call flightIsAvailable(fid, pId, fAvailable);
    if not fAvailable then
        return false;
    end if;

    if not seatExists(pId, sno) then
        return false;
    end if;

    if seatIsBought(fid, sno) then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if seatIsReserved then
        return false;
    end if;

    insert into Bought (FlightId, SeatNo)
    VALUES (fid, sno);
    return true;

end;
$$;

--  5.   BuyReserved(UserId, Pass, FlightId, SeatNo)
create function BuyReserved(in uid integer, in pwd varchar(34), in fid integer, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    pid            integer;
    fAvailable     boolean;
    seatIsReserved boolean;
    reservedUid    integer;
begin
    if not userExists(uid, pwd) then return false; end if;

    call flightIsAvailable(fid, pId, fAvailable);
    if not fAvailable then
        return false;
    end if;

    if not seatExists(pId, sno) then
        return false;
    end if;

    if seatIsBought(fid, sno) then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if not seatIsReserved or reservedUid != uid then
        return false;
    end if;

    delete
    from Reserved r
    where r.FlightId = fid
      and r.SeatNo = sno;

    insert into Bought (FlightId, SeatNo)
    VALUES (fid, sno);
    return true;
end;
$$;

--FlightsStatistics
create function FlightsStatistics(in uid integer, in pwd varchar(34))
    returns table
            (
                FlightId           integer,
                CanReserve         boolean,
                CanBuy             boolean,
                FreeSeatsCount     integer,
                ReservedSeatsCount bigint,
                BoughtSeatsCount   bigint
            )
    language plpgsql
as
$$
begin
    if not userExists(uid, pwd) then
        return query
            select 0, false, false, 0, cast(0 as bigint), cast(0 as bigint) limit 0;
    else
        begin

            return
                query
                select subQuery.FlightId,
                       subQuery.fs > 0,
                       subQuery.fs > 0 or subQuery.rsByUser > 0,
                       subQuery.fs,
                       subQuery.rs,
                       subQuery.bs
                from flightStatHelper(uid, pwd) subQuery;
        end;
    end if;
end;
$$;

--FlightStat
create function FlightStat(in uid integer, in pwd varchar(34), in fid integer)
    returns table
            (
                FlightId           integer,
                CanReserve         boolean,
                CanBuy             boolean,
                FreeSeatsCount     integer,
                ReservedSeatsCount bigint,
                BoughtSeatsCount   bigint
            )
    language plpgsql
as
$$

begin
    if not userExists(uid, pwd) then
        return query
            select 0, false, false, 0, cast(0 as bigint), cast(0 as bigint) limit 0;
    else
        begin

            return
                query
                select subQuery.FlightId,
                       subQuery.fs > 0,
                       subQuery.fs > 0 or subQuery.rsByUser > 0,
                       subQuery.fs,
                       subQuery.rs,
                       subQuery.bs
                from flightStatHelper(uid, pwd) subQuery
                where subQuery.FlightId = fid;
        end;
    end if;
end;
$$;

--CompressSeats
create function CompressSeats(in fid integer)
    returns boolean
    language plpgsql
as
$$
declare
    pid           integer;
    fAvailable    boolean;
    allSeats      varchar(4)[];
    boughtSeats   varchar(4)[];
    reservedSeats varchar(4)[];
    x             varchar(4);
    i             integer;
    nextBought    varchar(4)[];
    nextReserved  varchar(4)[];
    curs          refcursor;

begin
    call flightIsAvailable(fid, pid, fAvailable);
    if
        not fAvailable then
        return false;
    end if;

    delete
    from Reserved
    where EndTime < now();

    allSeats
        = array(select s.SeatNo from Seats s where s.PlaneId = pid order by length(s.SeatNo), s.SeatNo);
    boughtSeats
        = array(select b.SeatNo from Bought b where b.FlightId = fid);
    reservedSeats
        = array(select r.SeatNo from Reserved r where r.FlightId = fid and r.EndTime >= now());


    nextBought
        = allSeats[1:coalesce(array_length(boughtSeats, 1), 0)];
    nextReserved
        = allSeats[coalesce(array_length(boughtSeats, 1), 0) + 1:coalesce(array_length(boughtSeats, 1), 0) +
                                                                 coalesce(array_length(reservedSeats, 1), 0)];
    foreach x in array boughtSeats
        loop
            delete
            from Bought b
            where b.FlightId = fid
              and b.SeatNo = x;
        end loop;
    foreach x in array nextBought
        loop
            insert into Bought (FlightId, SeatNo) values (fid, x);
        end loop;


    open curs for select r.SeatNo from Reserved r where r.FlightId = fid and r.EndTime >= now();

    i = 1;
    loop
        FETCH NEXT FROM curs INTO x;
        if not found then
            exit;
        end if;
        update Reserved
        set SeatNo =nextReserved[i]
        where current of curs;
        i = i + 1;
    end loop;

    return true;
end;
$$;



create function test() returns boolean
    language plpgsql as
$$
declare
    pid int;
    uid int;
    res
        boolean;
begin
    call flightIsAvailable(300, pid, res);
    return res;
end;
$$;
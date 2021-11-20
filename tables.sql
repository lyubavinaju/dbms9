create table Flights
(
    FlightId   int primary key,
    FlightTime timestamp not null,
    PlaneId    int       not null
);

create table Seats
(
    PlaneId int        not null,
    SeatNo  varchar(4) not null,
    primary key (PlaneId, SeatNo)
);

create table Users
(
    UserId int primary key,
    Pass   varchar(16) not null
);

create table Bought
(
    FlightId int        not null,
    SeatNo   varchar(4) not null,
    primary key (FlightId, SeatNo),
    foreign key (FlightId) references Flights (FlightId)
);

create table Reserved
(
    FlightId int        not null,
    UserId   int        not null,
    SeatNo   varchar(4) not null,
    EndTime  timestamp  not null,
    primary key (FlightId, SeatNo),
    foreign key (FlightId) references Flights (FlightId),
    foreign key (UserId) references Users (UserId)
);



insert into Users (UserId, Pass)
VALUES (1, 'pass1'),
       (2, 'pass2'),
       (3, 'pass3');

insert into Seats (PlaneId, SeatNo)
VALUES (10, '100'),
       (10, '101'),
       (10, '102'),
       (20, '200'),
       (20, '201'),
       (20, '202'),
       (20, '206'),
       (20, '208'),
       (20, '218'),
       (30, '300');

insert into Flights (FlightId, FlightTime, PlaneId)
VALUES (100, make_date(2021, 12, 12), 30),
       (200, make_date(2021, 12, 12), 10),
       (300, make_date(2021, 12, 12), 20),
       (400, now() - interval '1 day', 20),
       (500, now() + interval '1 day', 20);

insert into Bought (FlightId, SeatNo)
VALUES (200, '101'),
       (300, '218');

insert into Reserved (FlightId, UserId, SeatNo, EndTime)
VALUES (300, 3, '202', now()),
       (100, 1, '300', now()),
       (300, 1, '201', now() + interval '1 day'),
       (300, 1, '208', now() + interval '1 day');



create procedure userExists(IN uid int, IN pwd varchar(16), INOUT res boolean)
    language plpgsql as
$$
begin
    res = exists(select * from Users u where u.UserId = uid and u.Pass = pwd);
end;
$$;

--check that flight is not outdated and find planeId
create procedure flightIsAvailable(in fid int, inout pid int, inout res boolean)
    language plpgsql as
$$
declare
    ftime timestamp;
begin
    select f.PlaneId, f.FlightTime into pid, ftime from Flights f where f.FlightId = fid;
    res = (pId is not null and fTime >= now());
end;
$$;

--check that plane has given seat
create procedure seatExists(in pid int, in sno varchar(4), inout res boolean)
    language plpgsql as
$$
begin
    res = exists(select * from Seats s where s.PlaneId = pid and s.SeatNo = sno);
end;
$$;

create procedure seatIsBought(in fid int, in sno varchar(4), inout res boolean)
    language plpgsql as
$$
begin
    res = exists(select * from Bought b where b.FlightId = fid and b.SeatNo = sno);
end;
$$;

create procedure seatIsReserved(in fid int, in sno varchar(4), inout uid int, inout res boolean)
    language plpgsql as
$$
declare
    resEndTime timestamp;
begin
    select r.EndTime, r.UserId into resEndTime, uid from Reserved r where r.FlightId = fid and r.SeatNo = sno;
    if resEndTime is not null then
        if resEndTime >= now() then
            res = true;
        else
            delete from Reserved r where r.FlightId = fid and r.SeatNo = sno;
            res = false;
        end if;
    else
        res = false;
    end if;
end;
$$;



-- 1. FreeSeats(FlightId)
create function FreeSeats(in fid int) returns varchar(4)[]
    language plpgsql
as
$$
declare
    fAvailable boolean;
    pid        int;
begin
    call flightIsAvailable(fid, pid, fAvailable);

    if not fAvailable then
        return array [] :: varchar(4)[];
    end if;
    raise notice '%', pid;
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
create function Reserve(in uid int,
                        in pwd varchar(16),
                        in fid int,
                        in sno varchar(4))
    returns boolean
    language plpgsql as
$$
declare
    uEx            boolean;
    pid            int;
    fAvailable     boolean;
    seatEx         boolean;
    seatIsBought   boolean;
    seatIsReserved boolean;
    reservedUid    int;

begin
    call userExists(uid, pwd, uEx);
    if not uEx then
        return false;
    end if;

    call flightIsAvailable(fid, pid, fAvailable);
    if not fAvailable then
        return false;
    end if;

    call seatExists(pid, sno, seatEx);
    if not seatEx then
        return false;
    end if;

    call seatIsBought(fid, sno, seatIsBought);
    if seatIsBought then
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
create function ExtendReservation(in uid int, in pwd varchar(16), in fid int, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    uEx            boolean;
    pid            int;
    fAvailable     boolean;
    seatEx         boolean;
    seatIsBought   boolean;
    seatIsReserved boolean;
    reservedUid    int;
begin
    call userExists(uid, pwd, uEx);
    if not uEx then
        return false;
    end if;

    call flightIsAvailable(fid, pid, fAvailable);
    if not fAvailable then
        return false;
    end if;

    call seatExists(pId, sno, seatEx);
    if not seatEx then
        return false;
    end if;

    call seatIsBought(fid, sno, seatIsBought);
    if seatIsBought then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if not seatIsReserved or reservedUid != uid then
        return false;
    end if;

    update Reserved set EndTime = now() + interval '3 days' where FlightId = fid and SeatNo = sno;
    return true;
end;
$$;

-- 4. BuyFree(FlightId, SeatNo)
create function BuyFree(in fid int, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    pid            int;
    fAvailable     boolean;
    seatEx         boolean;
    seatIsBought   boolean;
    seatIsReserved boolean;
    reservedUid    int;
begin
    call flightIsAvailable(fid, pId, fAvailable);
    if not fAvailable then
        return false;
    end if;

    call seatExists(pId, sno, seatEx);
    if not seatEx then
        return false;
    end if;

    call seatIsBought(fid, sno, seatIsBought);
    if seatIsBought then
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
create function BuyReserved(in uid int, in pwd varchar(16), in fid int, in sno varchar(4)) returns boolean
    language plpgsql as
$$
declare
    uEx            boolean;
    pid            int;
    fAvailable     boolean;
    seatEx         boolean;
    seatIsBought   boolean;
    seatIsReserved boolean;
    reservedUid    int;
begin
    call userExists(uid, pwd, uEx);
    if not uEx then
        return false;
    end if;

    call flightIsAvailable(fid, pId, fAvailable);
    if not fAvailable then
        return false;
    end if;

    call seatExists(pId, sno, seatEx);
    if not seatEx then
        return false;
    end if;

    call seatIsBought(fid, sno, seatIsBought);
    if seatIsBought then
        return false;
    end if;

    call seatIsReserved(fid, sno, reservedUid, seatIsReserved);
    if not seatIsReserved or reservedUid != uid then
        return false;
    end if;

    delete from Reserved r where r.FlightId = fid and r.SeatNo = sno;

    insert into Bought (FlightId, SeatNo)
    VALUES (fid, sno);
    return true;
end;
$$;

--FlightsStatistics
create function FlightsStatistics(in uid int, in pwd varchar(16))
    returns table
            (
                FlightId           int,
                CanReserve         boolean,
                CanBuy             boolean,
                FreeSeatsCount     int,
                ReservedSeatsCount bigint,
                BoughtSeatsCount   bigint
            )
    language plpgsql
as
$$
declare
    uEx boolean;
begin
    call userExists(uid, pwd, uEx);
    if not uEx then
        return query select 0, false, false, 0, cast(0 as bigint), cast(0 as bigint) limit 0;
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
                from (select f.FlightId,
                             coalesce(array_length(FreeSeats(f.FlightId), 1), 0)                                           as fs,
                             (select count(r.SeatNo) from Reserved r where r.FlightId = f.FlightId and r.EndTime >= now()) as rs,
                             (select count(r.SeatNo)
                              from Reserved r
                              where r.FlightId = f.FlightId
                                and r.EndTime >= now()
                                and r.UserId = uid)                                                                        as rsByUser,
                             (select count(b.SeatNo) from Bought b where b.FlightId = f.FlightId)                          as bs
                      from Flights f
                      where f.FlightTime >= now()) subQuery;
        end;
    end if;
end;
$$;

--FlightStat
create function FlightStat(in uid int, in pwd varchar(16), in fid int)
    returns table
            (
                FlightId           int,
                CanReserve         boolean,
                CanBuy             boolean,
                FreeSeatsCount     int,
                ReservedSeatsCount bigint,
                BoughtSeatsCount   bigint
            )
    language plpgsql
as
$$
declare
    uEx boolean;
begin
    call userExists(uid, pwd, uEx);
    if not uEx then
        return query select 0, false, false, 0, cast(0 as bigint), cast(0 as bigint) limit 0;
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
                from (select f.FlightId,
                             coalesce(array_length(FreeSeats(f.FlightId), 1), 0)                                           as fs,
                             (select count(r.SeatNo) from Reserved r where r.FlightId = f.FlightId and r.EndTime >= now()) as rs,
                             (select count(r.SeatNo)
                              from Reserved r
                              where r.FlightId = f.FlightId
                                and r.EndTime >= now()
                                and r.UserId = uid)                                                                        as rsByUser,
                             (select count(b.SeatNo) from Bought b where b.FlightId = f.FlightId)                          as bs
                      from Flights f
                      where f.FlightId = fid
                        and f.FlightTime >= now()) subQuery;
        end;
    end if;
end;
$$;

--CompressSeats
create function CompressSeats(in fid int)
    returns boolean
    language plpgsql
as
$$
declare
    pid           int;
    fAvailable    boolean;
    allSeats      varchar(4)[];
    boughtSeats   varchar(4)[];
    reservedSeats varchar(4)[];
    x             varchar(4);
    i             int;
    nextBought    varchar(4)[];
    nextReserved  varchar(4)[];
    curTime       timestamp;
    curs          refcursor;

begin
    call flightIsAvailable(fid, pid, fAvailable);
    if not fAvailable then
        return false;
    end if;

    curTime = now();
    delete from Reserved where EndTime < curTime;

    allSeats = array(select s.SeatNo from Seats s where s.PlaneId = pid order by s.SeatNo);
    boughtSeats = array(select b.SeatNo from Bought b where b.FlightId = fid order by b.SeatNo);
    reservedSeats = array(select r.SeatNo from Reserved r where r.FlightId = fid and r.EndTime >= curTime order by r.SeatNo);


    nextBought = allSeats[1:coalesce(array_length(boughtSeats, 1), 0)];
    nextReserved = allSeats[coalesce(array_length(boughtSeats, 1), 0) + 1:coalesce(array_length(boughtSeats, 1), 0) +
                                                                          coalesce(array_length(reservedSeats, 1), 0)];
    foreach x in array boughtSeats
        loop
            delete from Bought b where b.FlightId = fid and b.SeatNo = x;
        end loop;
    foreach x in array nextBought
        loop
            insert into Bought (FlightId, SeatNo) values (fid, x);
        end loop;


    open curs for select r.SeatNo from Reserved r where r.FlightId = fid and r.EndTime >= curTime order by r.SeatNo;

    i = 1;
    loop
        FETCH NEXT FROM curs INTO x;
        if not found then
            exit;
        end if;
        update Reserved set SeatNo =nextReserved[i] where current of curs;
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
    res boolean;
begin
    call flightIsAvailable(400, pid, res);
    return res;
end;
$$;
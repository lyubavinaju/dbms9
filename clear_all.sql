drop function if exists FreeSeats;
drop function if exists Reserve;
drop function if exists ExtendReservation;
drop function if exists BuyFree;
drop function if exists BuyReserved;

drop function if exists FlightsStatistics;
drop function if exists FlightStat;

drop function if exists CompressSeats;



drop procedure if exists userExists;
drop procedure if exists flightIsAvailable;
drop procedure if exists seatExists;
drop procedure if exists seatIsBought;
drop procedure if exists seatIsReserved;


drop table if exists Reserved;
drop table if exists Bought;
drop table if exists Users;
drop table if exists Seats;
drop table if exists Flights;


drop function if exists test;
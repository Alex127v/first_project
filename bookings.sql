/*Выведите название самолетов, которые имеют менее 50 посадочных мест*/

select a.model
from aircrafts a 
join seats s 
on a.aircraft_code = s.aircraft_code
group by a.aircraft_code
having count(s.seat_no) < 50

/*
Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых
Поскольку месяцы могут быть с пропусками, я создам доп столбец с непрерывной последовательностью месяцев*/

select  t1.month_series, round(                                                  -- Округляем до сотых
						((t2.sum - lag(t2.sum) over(order by t1.month_series)) / -- Вычитаем из текущего месяца предыдущий
						lag(t2.sum) over(order by t1.month_series))*100, 2       -- Делим на значение предыдущего месяца
						) as change_share     												
from (select generate_series(                                    -- Генерируем непрерывную последовательность месяцев между min max
	   min(date_trunc('month', b.book_date::date)), max(date_trunc('month', b.book_date::date)), '1 month'::interval
	   ) as month_series
      from bookings b) t1
left join (select date_trunc('month', book_date::date) as month, --Достаем выручку по месяцам из базовой таблицы
				  sum(total_amount ) as sum
		   from bookings 
		   group by date_trunc('month', book_date::date)
		   order by date_trunc('month', book_date::date)) t2
on t1.month_series = t2.month                                  -- Соединяем нашу непрерывную последовательность с базовой таблицей, по месяцу

/*Выведите названия самолетов не имеющих бизнес - класс. Решение должно быть через функцию array_agg*/

select a.model
from (select s.aircraft_code, array_agg(distinct s.fare_conditions) as condition -- Из таблицы seats собираем массив классов для каждого самолета
	  from seats s 
	  group by s.aircraft_code
	  having not 'Business' = any(array_agg(distinct s.fare_conditions))) t1     -- Фильтруем строки которые НЕ содержат в массиве класс 'Business'
join aircrafts a                                                                 -- Соединяем с таблицей самолетов и получаем модель
on t1.aircraft_code = a.aircraft_code

/*
Вывести накопительный итог количества мест в самолетах по каждому аэропорту на каждый день, учитывая только 
те самолеты, которые летали пустыми и только те дни, где из одного аэропорта таких самолетов вылетало более одного.
В результате должны быть код аэропорта, дата, количество пустых мест и накопительный итог*/

select  t1.airport_code, t1.actual_departure, t1.empty,
       -- В окне на каждый аэропорти день, считаем сумму внутри каждого дня, накопительно  
	   sum(t1.empty) over(partition by t1.airport_code, t1.actual_departure::date order by t1.actual_departure)
from(select f.flight_id, bp.flight_id, a.airport_code, f.actual_departure, s.empty,
			count(*) over(partition by a.airport_code, f.actual_departure::date) as count_aircraft		
	from flights f                     -- Берём таблицу перелетов
	left join (select flight_id        -- Присоединяем таблицу посадочных талонов, сгруппированную по перелетам  
			   from boarding_passes    -- чтоб они были уникальны
			   group by flight_id) bp
	on f.flight_id = bp.flight_id
	join airports a                    -- Присоединяем таблицу аэропортов по аэропорту вылета в таблице перелетах
	on f.departure_airport = a.airport_code
	join (select aircraft_code, count(seat_no) as empty --Присоединяем таблицу с количеством мест в в каждом самолете
		  from seats
		  group by aircraft_code) s
	on f.aircraft_code = s.aircraft_code                             -- Нам нужны выполненые перелеты поэтому фильтр по статусу
	where f.status in ('Depature', 'Arrived') and bp.flight_id is null) t1 -- и пустые - это те, которых нет в таблице посадочных
where t1.count_aircraft > 1    -- Фильтруем только те аэропорты откуда вылетали более 2 бортов

/*Найдите процентное соотношение перелетов по маршрутам, от общего количества перелетов.
Выведите в результат названия аэропортов и процентное отношение.*/

select f.departure_airport_name, f.arrival_airport_name,           --Названия аэропортов
	   round((count(*)*100.0/ sum(count(*)) over()), 2) as perсent --Количество маршрутов (т.е. сгруппированных по аэр взлета 
from flights_v f                                                   --и посадке) делим на сумму всех этих маршрутов(сумма это все
group by f.departure_airport_name, f.arrival_airport_name          -- перелеты) умножаем на 100, и получаем искомый процент
order by f.departure_airport_name                                  --Сортируем по аэродрому вылета для эстетики


/*Выведите количество пассажиров по каждому коду сотового оператора, если учесть,
   что код оператора - это три символа после +7 . Данные у нас в jsonb ключ phone*/

select substring(contact_data->>'phone' from 3 for 3), count(passenger_id)
from tickets                                    
where contact_data ? 'phone' and contact_data->>'phone' like '+7%'--Проерка что ключ 'phone' содержится в массиве и начинается с +7
group by substring(contact_data->>'phone' from 3 for 3)           --Группировка по 3 символам после +7


/*Классифицируйте финансовые обороты (сумма стоимости перелетов) по маршрутам:
До 50 млн - low
От 50 млн включительно до 150 млн - middle
От 150 млн включительно - high
Выведите в результат количество маршрутов в каждом полученном классе*/

select t1.financial_class, count(t1.flight_no) as count_flight_no
from    (select f.flight_no, sum(tf.amount)/1000000 as total_sum,       --Для классификации, получим сумму по каждому маршруту
			case                                                        --поделим ее на 1млн, для удобства, и воспользуемся
				when sum(tf.amount)/1000000 < 50 then 'Low'             --case-для присвоения класса.
				when sum(tf.amount)/1000000 < 150 and sum(tf.amount)/1000000 >= 50 then 'Middle'
				else 'High'
			end as financial_class
		from flights f                                                   
		join ticket_flights tf                                           --Присоединим табицу ticket_flights с информацией о 
		on f.flight_id = tf.flight_id                                    --стоимости перелета   
		group by f.flight_no) as t1                                      --Группируем по номеру маршрута в подзапросе
group by t1.financial_class                                              --Для результата группируем по классу оборота

/*Вычислите медиану стоимости перелетов, медиану размера бронирования и отношение
 медианы бронирования к медиане стоимости перелетов, округленной до сотых*/

with                                                                       --Сделаем два подзапроса через cte
cte1 as (                                                                  --В первом считаем медиану перелетов
select percentile_cont(0.5) within group (order by amount) as median_flight
from ticket_flights tf),
cte2 as (                                                                  --Во втором считаем медиану бронирования
select percentile_cont(0.5) within group (order by total_amount) as median_booking
from bookings b)
select round(median_booking::numeric/median_flight::numeric, 2)            --Считаем отношение медиан, округляем до сотых
from cte1
cross join  cte2

/*Найдите значение минимальной стоимости полета 1 км для пассажиров. 
То есть нужно найти расстояние между аэропортами и с учетом стоимости перелетов получить искомый результат*/


CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;


with cte1 as (                                         --Сделаем подзапрос через cte1
select f.flight_id, tf.fare_conditions, 
                    tf.amount/                            
	               (earth_distance(                    --earth_distance(point1, point2) вычисляет расстояние между                        
				    -- Точка 1 (широта, долгота)        --двумя такими точками             
				    ll_to_earth(a1.latitude, a1.longitude),  --ll_to_earth(lat, lon) преобразует географические                  
				    -- Точка 2 (широта, долгота)     --координаты (широта, долгота) в трехмерные декартовы координаты                              
				    ll_to_earth( a2.latitude, a2.longitude))/1000) AS rub_km         --на поверхности сферы                                    
from flights f                                                     
join ticket_flights tf                                  --Присоединяем все необходимые таблицы - аэропорты с координатами            
on f.flight_id = tf.flight_id                           --и билеты со стоимостью
join airports a1 
on f.departure_airport = a1.airport_code 
join airports a2 
on f.arrival_airport = a2.airport_code)
select  round(min(rub_km)::numeric, 2)         --Искомое минимальное значение стоимости
from cte1







	


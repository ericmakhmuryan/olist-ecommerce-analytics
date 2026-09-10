-- ===================================================================
-- QUESTION 1: Revenue Impact & Churn Rate
-- How many customers churned vs. stayed, and how much money is lost?
-- ===================================================================
select 
	is_churned,
	count(distinct customer_unique_id) as total_customers,
	round(sum(total_payment_value)::numeric, 2) as total_revenue
from fact_orders
group by is_churned

 
-- ===================================================================
-- QUESTION 2: Top Revenue Product Categories
-- Which product categories bring in the most money and what is their churn rate?
-- ===================================================================
select 
	product_category_name,
	count(order_id) as total_orders,
	round(sum(total_payment_value)::numeric, 2) as total_revenue,
	round(avg(is_churned) * 100, 1) as churn_rate_percentage
from fact_orders 
where product_category_name is not null
group by product_category_name 
order by total_revenue desc
limit 15;


-- ===================================================================
-- QUESTION 3: Installment Tiers vs. Churn
-- How does splitting payments into installments affect churn?
-- ===================================================================

with Payment_Grouped as (
	select primary_payment_type, order_id,
	case 
		when max_payment_installments = 1 then '1x (Upfront)'
		when max_payment_installments between 2 and 6 then '2x-6x (Short Term)'
		when max_payment_installments between 7 and 12 then '7x-12x (Mid Term)'
		else '13x+ (Long Term)'
	end as installment_tier,
	is_churned,
	total_payment_value
	from fact_orders
	where primary_payment_type is not null
)

select 
	primary_payment_type,
	installment_tier,
	count(order_id) as total_orders,
	round(sum(total_payment_value)::numeric, 2) as total_revenue,
	round(avg(is_churned) * 100, 1) as churn_rate_percentage
from Payment_Grouped
group by primary_payment_type, installment_tier 
order by primary_payment_type, total_revenue desc;

/*
 buyers opt for longer installment plans (7x+), the churn rate increases noticeably—proving that long-term financing 
 attracts single-purchase buyers for high-ticket items rather than repeat platform users.
 */


-- ===================================================================
-- QUESTION 4: Revenue Lost by Customer Spending Quartile
-- Are we losing high-value spenders or budget buyers to churn?
-- ===================================================================

with CustomerTiers as (
	select
		customer_unique_id,
		is_churned,
		sum(total_payment_value) AS customer_spend,
		ntile(4) over (order by sum(total_payment_value) desc) as spend_quartile
	from fact_orders 
	group by customer_unique_id, is_churned
)
select spend_quartile,
count(customer_unique_id) as customer_count,
round(avg(is_churned) * 100, 1) as churn_rate_percentage,
-- Conditional Sums to separate lost vs retained dollars
round(sum(case when is_churned = 1 then customer_spend else 0 end)::numeric, 2) as lost_revenue, 
round(sum(case when is_churned = 0 then customer_spend else 0 end)::numeric, 2) as retained_revenue
from CustomerTiers 
group by spend_quartile
order by spend_quartile





-- ===================================================================
-- QUESTION 5: Delivery Delay Ranking by State
-- Which states have the worst delivery delays, and how are they ranked?
-- ===================================================================


with StatePerformance as (
	select 
		customer_state,
		count(order_id) as total_orders,
		round(avg(delivery_time_days)::numeric, 1) as avg_delivery_days,
		round(avg(is_churned) * 100, 1) as churn_rate_percentage
	from fact_orders 
	group by customer_state 
	having count(order_id) > 500
)
select 
	customer_state,
	total_orders,
	avg_delivery_days,
	churn_rate_percentage,

	rank() over (order by churn_rate_percentage desc ) as churn_rank 
from StatePerformance
order by churn_rank 

--shipping delays in specific states directly correlate with higher customer churn.



-- ===================================================================
-- QUESTION 6: Delivery Promise Variance vs. Churn
-- Compares fulfillment against estimated dates (Early, On-Time, Late)
-- ===================================================================

with DeliveryAccuracy as (
	select 
		order_id,
		is_churned,
		total_payment_value,
     	delivery_time_days,
        estimated_vs_actual_days,
		case 
			when estimated_vs_actual_days > 10 then 'Delivered 10+ Days Early'
			when estimated_vs_actual_days between 1 and 10 then 'Delivered On-Time / Slightly Early'
			when estimated_vs_actual_days between -5 and 0 then 'Late (1-5 Days Delay)'
			else 'Severely Late (5+ Days Delay)'
		end as delivery_performance
	from fact_orders 
	where delivery_time_days is not null
)

select 
delivery_performance,
count(order_id) as total_orders,
round(avg(delivery_time_days)::numeric ,1) as avg_actual_delivery_days,
round(avg(is_churned) * 100, 1) as churn_rate_percentage,
round(sum(case when is_churned = 1 then total_payment_value else 0 end)::numeric, 2) as lost_revenue
from DeliveryAccuracy
group by delivery_performance
order by churn_rate_percentage asc;

/*
We discovered that orders delivered 10+ days late experienced the highest churn rates, accounting for a massive chunk
of lost revenue. 
*/

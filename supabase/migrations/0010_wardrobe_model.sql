-- Wardrobe v2: one count row per clothing category (qty = count, cost_paise =
-- typical price per item), and photos as their own 'wardrobe_photo' rows so each
-- category shows a gallery. Consolidate the old one-row-per-item data.

-- Existing photo'd clothing rows become gallery photos.
update belongings set kind = 'wardrobe_photo' where kind = 'clothing' and image_path is not null;

-- Keep the earliest count row per (user, category) and give it the summed qty.
with ranked as (
	select
		id,
		row_number() over (partition by user_id, category order by created_at, id) as rn,
		sum(qty) over (partition by user_id, category) as total
	from belongings
	where kind = 'clothing'
)
update belongings b set qty = r.total::int from ranked r where b.id = r.id and r.rn = 1;

delete from belongings b using (
	select id, row_number() over (partition by user_id, category order by created_at, id) as rn
	from belongings where kind = 'clothing'
) r
where b.id = r.id and r.rn > 1;

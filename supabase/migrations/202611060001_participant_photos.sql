alter table public.participants
  add column photo_data text;

alter table public.participants
  add constraint participants_photo_data_size_check
  check (
    photo_data is null
    or (
      length(photo_data) <= 450000
      and photo_data like 'data:image/jpeg;base64,%'
    )
  );

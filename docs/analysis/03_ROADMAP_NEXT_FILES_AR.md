# خارطة الدفعات القادمة (كل دفعة = ملفات كاملة جاهزة للنسخ)

الدفعة 1 (جاهزة): حارس الإطارات الخضراء + التشخيص + تحليل المراجع.

الدفعة 2 — مشاهد موشن غنية وربط الكاميرا:
- `lib/scene_richness_guard.dart` (جديد): يرفض أي مشهد فيه أقل من 4 طبقات مرئية (خلفية + شخصية + نص + جزيئات/overlay).
- `lib/continuous_scene_generator.dart`: إجبار حد أدنى للطبقات وشخصية ثابتة طوال الفيديو (سمة `mascot` واحدة لكل تصدير).
- `lib/motion_transitions.dart`: إضافة whip-pan و zoom-through و pixel-dissolve تبدأ من لقطة الشخص (match-cut).
- `lib/enhancer.dart`: تمرير آخر إطار من لقطة الشخص كأول إطار للمشهد.

الدفعة 3 — B-roll:
- `lib/broll.dart` + `lib/enhancer.dart`: استعلام بجملة لا كلمة، فحص صلة بالذكاء الاصطناعي، وإلغاء الـ crossfade الذي يترك شبحاً.

الدفعة 4 — الكابشن والعنوان:
- `lib/caption_style_engine.dart` / `lib/enhancer.dart`: موضع ديناميكي يتجنب اليد والمايك (من `person_tracker`)، وخروج بحركة للعنوان.

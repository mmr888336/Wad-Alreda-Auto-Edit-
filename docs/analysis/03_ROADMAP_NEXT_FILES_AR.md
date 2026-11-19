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

---
## الدفعة 2 (جاهزة): `scene_richness_guard.dart`
- أي مشهد موشن فيه أقل من 4 طبقات مرئية أو أقل من overlay متحركين يأخذ: كلمة عملاقة باهتة خلف العنصر (عمق بعيد + حركة بطيئة، مثل المرجع) + جزيئات متحركة (embers/sparkles/bokeh/dust).
- مربوط في `MotionCutawayRenderer.render` قبل `DepthCameraPlanner`؛ أي خطأ = المشهد يبقى كما بُني.
- للإيقاف: `SceneRichnessGuard.enabled = false`.
- المتبقي من الدفعة 2 (شخصية ثابتة + انتقال match-cut من لقطة الشخص) يحتاج لمس `reference_scene_builder.dart` (778 سطر) و`enhancer.dart` وسيأتي في الدفعة 2ب.

---
## الدفعة 3 (جاهزة): `broll_relevance_guard.dart`
- يستبعد اقتراحات B-roll العامة ("kitchen", "man in room"...) لأنها سبب مقطع البيضة المقلية؛ يبقي فقط ما فيه كلمتان محددتان فأكثر ومدته 1.8 ث فأكثر.
- حد أقصى 3 مقاطع مخزون في الفيديو (مشاهد الموشن تحمل القصة البصرية).
- مربوط في `enhancer.dart` (فلترة الأفكار + الحد)، وملاحظة تظهر في تقرير التصدير بعدد المستبعد.
- للإيقاف: `BrollRelevanceGuard.enabled = false`.

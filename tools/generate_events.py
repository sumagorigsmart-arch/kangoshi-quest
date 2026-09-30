"""Maintain the authored Phase 3 event pool; run to regenerate the JSON asset."""
import json
from pathlib import Path

# id, title, description, category, window, choice labels, pending task kind
ROWS = [
('call_water','水を一杯','ナースコールで水を頼まれた。同時に朝の記録も開いたまま。','call',(510,760),('部屋へ行き様子も聞く','近くの仲間に頼み記録を進める','水を届けて記録は後に回す'),'record'),
('vitals_round','朝のバイタル','予定の測定中、別室のコールが重なる。','care',(510,610),('気になる値を再確認する','予定分を先に回り切る','仲間と分担して測る'),'care'),
('iv_alarm','点滴ポンプの音','点滴のアラーム。処置の準備も時間が迫る。','care',(510,835),('現場で原因まで確認する','安全を確認し準備へ戻る','応援を呼んで一緒に確認する'),'record'),
('morning_meds','朝の内服','内服の確認と、食事を待つ患者への声かけが同時に来た。','care',(510,635),('一人ずつ説明して渡す','必要事項を確認して手際よく渡す','仲間と分担し食事にも目を配る'),'record'),
('blood_draw','採血の順番','採血の順番を待つ間に書類が積まれていく。','care',(510,685),('落ち着いて採血と説明をする','採血を先に済ませ記録を後にする','待ち時間に書類を一件片付ける'),'record'),
('exam_transport','検査へ出発','検査室から呼び出し。移送と病棟のケアが重なる。','coordination',(535,810),('移送に付き添い確認する','連絡を整えて移送を頼む','準備を優先しケアは後で行う'),'coordination'),
('linen_change','シーツ交換','清潔ケアの希望と予定の処置がぶつかった。','care',(535,885),('本人の希望に合わせて交換する','処置を先にし交換は後で行う','仲間と一緒に短時間で整える'),'care'),
('breakfast_help','朝食の介助','食事の手助けを求める声。医師からの確認も待っている。','care',(535,660),('食べられるまで付き添う','安全を確認して連絡を先にする','チームと分担し食事を進める'),'record'),
('toilet_call','トイレのコール','トイレ介助のコール。自分もトイレに行きたい。','call',(560,935),('患者の移動をゆっくり支える','仲間に声をかけ自分もトイレへ行く','安全を確認し手早く介助する'),'care'),
('fall_prevention','立ち上がりの気配','転倒リスクのある患者が一人で立ち上がろうとしている。','care',(560,960),('そばで話を聞き環境を整える','すぐ支え必要な声かけをする','仲間を呼び対応を分担する'),'care'),
('doctor_question','医師への確認','曖昧な指示を確認したいが、電話はつながりにくい。','coordination',(560,910),('確認が取れるまで調整する','要点を整理して折り返しを待つ','リーダーに状況を共有する'),'coordination'),
('new_order','指示変更','指示が更新された。患者説明と記録の順番に迷う。','coordination',(585,960),('変更内容を丁寧に説明する','記録とチーム共有を先にする','要点だけ伝え詳細説明を後にする'),'record'),
('family_visit','面会の質問','家族から今日の見通しを聞かれた。別室の処置も始まる。','family',(585,935),('時間を取り落ち着いて話す','要点を伝え処置へ向かう','担当者につないで共有を残す'),'coordination'),
('phone_lab','検査室からの電話','検査室から確認の電話。患者の待ち時間も伸びている。','coordination',(585,860),('条件を一つずつ照合する','要件をまとめて折り返す','リーダーに確認を頼み患者へ戻る'),'coordination'),
('junior_support','新人からの相談','新人が処置の段取りを確認したいと言う。自分の記録も残る。','team',(610,935),('一緒に手順を整理する','要点を伝えて記録へ戻る','別の仲間も交えて役割を分ける'),'record'),
('colleague_request','同僚からの頼み','同僚のケアが重なり助けを求められた。自分の予定も詰まる。','team',(610,960),('今すぐ一緒にケアへ入る','今できる範囲を伝える','互いの予定を見て分担を組み直す'),'care'),
('leader_request','リーダーからの依頼','急な病棟全体の確認依頼。個人の残務が押している。','team',(610,990),('全体の確認を引き受ける','締切を相談して自分の仕事を進める','範囲を絞って他の人と分ける'),'coordination'),
('chart_gap','記録の空欄','朝の記録に空欄を見つけた。次のケアに向かう時間だ。','record',(635,1005),('今ここで確認して埋める','要点をメモしケアへ向かう','仲間に状況を伝え記録を進める'),'record'),
('care_plan','看護計画の見直し','状態変化に合わせた計画の見直し。患者との会話も必要。','record',(635,990),('患者と話し計画を整える','先に計画だけ更新する','チームに観察を頼み記録を進める'),'record'),
('admission_notice','入院の連絡','新しい入院の連絡。ベッド準備と担当患者のケアが同時だ。','admission',(635,935),('受け入れまで自分で整える','準備を分担してケアを続ける','受け入れ時刻を調整する'),'coordination'),
('discharge_papers','退院書類','退院の書類が届いた。説明を待つ家族と病棟電話が重なる。','discharge',(660,960),('書類を確認し丁寧に説明する','書類を先にまとめ説明を短くする','担当者と分担して確認する'),'record'),
('transfer_bed','転棟の段取り','転棟の時刻が変わった。移送と申し送りを組み直す。','coordination',(660,990),('受け入れ先と細部まで確認する','要点を先に送り残りを後で整える','リーダーと分担を相談する'),'coordination'),
('lunch_tray','昼食の配膳','食事が届いた。患者の食事介助と自分の昼食が重なる。','care',(685,810),('患者のペースで介助する','安全を確認して自分も食べる','仲間と交代で食事を支える'),'care'),
('water_bottle','水分のひと口','喉が渇いた。次のコールと連絡がすぐ来そうだ。','self',(685,1005),('少し休み水を飲む','連絡を片付けてから飲む','水を飲みながら段取りを共有する'),'coordination'),
('staff_break','休憩の順番','休憩交代の順番が来たが、ケアの予定がずれ込んでいる。','self',(710,860),('交代を頼んで休憩に入る','ケアを終えてから休憩する','休憩を短く区切り引き継ぐ'),'care'),
('toilet_self','自分のトイレ','トイレを我慢している。今なら少しだけ抜けられる。','self',(710,1005),('仲間に伝えてトイレへ行く','もう一件終わらせてから行く','用件を整理し短く交代を頼む'),'record'),
('snack_choice','空腹の合図','空腹で集中が落ちてきた。午後の処置が始まる。','self',(735,960),('軽く食べてから向かう','先に処置へ向かう','仲間と順番を相談して食べる'),'care'),
('acute_warning','急変の兆し','いつもと違う反応。ほかの患者の予定も同時に動いている。','acute',(735,960),('そばを離れずチームを呼ぶ','必要な確認をして連絡する','役割分担を明確にして対応する'),'record'),
('procedure_queue','処置が重なる','複数の処置が同じ時間に集まった。順番を決める必要がある。','care',(735,990),('患者の状態を見て丁寧に進める','緊急度で順番を決め手早く進める','チームに相談して分担する'),'care'),
('recheck_vitals','再測定','気になる値の再測定を頼まれた。記録はまだ途中。','care',(760,1005),('変化を確認して報告する','再測定を済ませ記録に戻る','仲間に共有して記録を片付ける'),'record'),
('diet_change','食事形態の変更','食事形態の連絡が届く。配膳と確認が同時に進む。','coordination',(760,860),('本人と厨房まで確認する','配膳を止め要点だけ確認する','担当部署と分担して調整する'),'coordination'),
('paper_signature','書類の署名','署名が必要な書類が回ってきた。患者のコールも鳴っている。','record',(760,1005),('内容を読み切って説明する','先にコールへ向かい書類を残す','仲間と分担し書類を確認する'),'record'),
('bed_clean','ベッドの準備','次の入院に備えるベッドと、今いる患者の清潔ケア。','care',(785,960),('両方の準備を丁寧に進める','今いる患者のケアを先にする','入院準備を仲間に頼む'),'care'),
('family_call','家族からの電話','家族が状況を気にかけている。病棟の予定も押し始めた。','family',(785,1005),('今の様子を丁寧に伝える','要点を伝え後で連絡する','リーダーと情報を合わせて返答する'),'coordination'),
('pharmacy_check','薬剤部との確認','薬剤部から確認が入る。患者説明と記録が並ぶ。','coordination',(785,990),('指示を照合して丁寧に返す','要点を返して記録へ戻る','医師と薬剤部の確認を調整する'),'coordination'),
('late_call','午後のナースコール','午後のコールが続く。記録の進み具合が気になる。','call',(810,1005),('一件ずつ話を聞き対応する','安全を確認し記録も進める','仲間とコールを分担する'),'record'),
('mobility_help','歩行の付き添い','歩く練習をしたい患者。転倒への注意と時間が必要だ。','care',(810,990),('本人のペースで付き添う','短い距離に絞って付き添う','他職種と時刻を調整する'),'care'),
('discharge_followup','退院後の確認','退院後の連絡先を確認したい。別の患者のケアも待つ。','discharge',(835,1005),('家族と一緒に確認する','資料を渡し要点を伝える','相談員と確認を分担する'),'coordination'),
('change_in_plan','予定の組み直し','検査時刻の変更が重なり、午後の予定を組み直す。','coordination',(835,1005),('関係部署に順番に連絡する','優先順位だけ決めて動く','リーダーと全体を組み直す'),'coordination'),
('record_backlog','記録の山','未入力の記録が目につく。コールも気になって手が止まる。','record',(860,1020),('記録をまとめて片付ける','重要事項だけ先に入力する','チームへ状況を伝えて集中する'),'record'),
('afternoon_toilet','排泄ケア','排泄の介助を頼まれた。申し送りの準備も始まる。','care',(860,1005),('プライバシーに配慮し介助する','介助して申し送り準備へ戻る','近くの仲間と役割を分ける'),'record'),
('evening_meds','夕方の内服確認','夕方の内服の確認。帰り際の書類も届いた。','care',(885,1020),('本人と一緒に確認して渡す','必要事項を確認して書類へ戻る','仲間と分担して確認する'),'record'),
('shift_phone','終業前の電話','終業前の電話。次の勤務に伝える情報が増えた。','coordination',(910,1020),('内容を詳しく確認して共有する','要点を記録し後で伝える','リーダーと伝達を分担する'),'coordination'),
('handover_notes','申し送りメモ','最終申し送りのメモが散らばっている。ケアもまだ一件残る。','record',(910,1020),('メモを整理してからケアへ向かう','ケアを済ませてから整理する','チームと情報を突き合わせる'),'record'),
('last_round','最後の巡視','定時が見えてきた。最後の巡視と記録の締めが重なる。','care',(935,1020),('一室ずつ様子を確かめる','気になる部屋を優先する','仲間と分担して見て回る'),'record'),
('late_admission','遅い入院連絡','夕方に入院予定の連絡。準備と申し送りが同時に迫る。','admission',(935,1020),('受け入れ準備を進める','必要な準備だけ先に整える','受け入れ先とチームで分担する'),'coordination'),
('new_order_late','夕方の追加指示','新しい指示が届いた。引き継ぐ前に確認しておきたい。','coordination',(960,1020),('医師に確認して情報をまとめる','必要事項を先に共有する','リーダーと確認を分担する'),'coordination'),
('call_near_end','帰り際のコール','帰り際にコール。本人も遠慮がちで、記録はまだ開いたまま。','call',(960,1020),('時間を取って気持ちも聞く','必要な対応をして記録へ戻る','仲間と状況を共有する'),'record'),
('form_correction','書類の差し戻し','書類の記載を直してほしいと戻ってきた。申し送りも近い。','record',(990,1020),('内容を確認し丁寧に直す','必要箇所を直して先へ進む','担当者に確認して手分けする'),'record'),
('last_coordination','最終調整','他部署との連絡が一本残った。患者の様子も最後に見たい。','coordination',(990,1020),('連絡と患者確認を両方行う','先に連絡を済ませる','チームと連絡を分担する'),'coordination'),
]

RANDOM_IDS = {r[0] for r in ROWS[::4]}  # 13 authored uncertain situations
SELF_IDS = {'water_bottle', 'staff_break', 'toilet_self', 'snack_choice'}
MAJOR_IDS = {'acute_warning', 'late_admission', 'fall_prevention', 'admission_notice'}
CALL_IDS = {'call_water', 'toilet_call', 'late_call', 'call_near_end'}

def task(kind, amount=1):
    return {kind: amount}

def effects(minutes, *, meter=None, score=None, create=None, complete=None, rest=0, toilet=False):
    result = {'durationMinutes': minutes}
    if meter: result['meterDelta'] = meter
    if score: result['scoreDelta'] = score
    if create: result['createTasks'] = create
    if complete: result['completeTasks'] = complete
    if rest or toilet: result['counters'] = {**({'breakMinutes': rest} if rest else {}), **({'toiletCount': 1} if toilet else {})}
    if toilet: result['setBladderAfter'] = 1000
    return result

def choice(id, label, hint, action, main, alternative=None):
    outcomes = [{'outcomeId': 'expected', 'weight': 3 if alternative else 1,
                 'text': main[0], 'effects': main[1]}]
    if alternative:
        outcomes.append({'outcomeId': 'interruption', 'weight': 1,
                         'text': alternative[0], 'effects': alternative[1]})
    return {'choiceId': id, 'label': label, 'hint': hint, 'actionType': action, 'outcomes': outcomes}

events = []
for index, (id, title, description, category, window, labels, pending) in enumerate(ROWS):
    self_event = id in SELF_IDS
    base = 12 + index % 5
    # Some encounters leave follow-up work; others are finished during the encounter.
    detailed = effects(base + 4, meter={'hp': -100, 'mental': 80}, score={'patient': 250, 'team': 60},
                       create=task(pending) if index % 5 == 0 else None)
    fast = effects(7 + index % 3, meter={'hp': -60, 'mental': -80}, score={'patient': -80, 'risk': 120},
                   create=task(pending) if index % 4 == 0 else None)
    shared = effects(max(9 + index % 4, {'record':6,'coordination':8,'care':10}[pending]), meter={'mental': 100}, score={'team': 160, 'patient': 40}, complete=task(pending))
    if self_event:
        detailed = effects(12, meter={'hp': 350, 'mental': 300, 'hunger': -900}, rest=10)
        fast = effects(max(7, {'record':6,'coordination':8,'care':10}[pending]), meter={'hp': -70, 'mental': -100}, score={'risk': 100}, complete=task(pending))
        shared = effects(9, meter={'hp': 180, 'mental': 130, 'hunger': -350}, score={'team': 80}, rest=6)
    if id == 'toilet_self':
        detailed = effects(5, meter={'mental': 200}, toilet=True)
        shared = effects(7, meter={'mental': 100}, score={'team': 80}, toilet=True)
    if id == 'toilet_call':
        shared = effects(10, meter={'mental': 150}, score={'team': 80}, toilet=True)
    alt = None
    if id in RANDOM_IDS:
        alt = (f'{title}の途中で別の用件が重なり、対応を記録して次へつないだ。',
               effects(base + 8, meter={'mental': -160, 'hp': -120}, score={'patient': 80, 'team': -80}, create=task(pending)))
    conditions = []
    if id == 'toilet_self': conditions = [{'field':'meters.bladder','op':'gte','value':3500}]
    if id == 'snack_choice': conditions = [{'field':'meters.hunger','op':'gte','value':3000}]
    if id == 'record_backlog': conditions = [{'field':'tasks.record','op':'gte','value':2}]
    if id == 'water_bottle': conditions = [{'field':'meters.hp','op':'lte','value':7500}]
    tags = (['major'] if id in MAJOR_IDS else []) + (['call'] if id in CALL_IDS else [])
    if id in {'toilet_self','toilet_call'}: tags.append('toilet')
    if id in {'snack_choice','lunch_tray'}: tags.append('food')
    if window[0] >= 935: tags.append('lateShift')
    modifiers = []
    if id in RANDOM_IDS:
        modifiers.append({'conditions':[{'field':'scores.team','op':'lte','value':4000}], 'factor':1.6})
    if pending == 'record':
        modifiers.append({'conditions':[{'field':'tasks.record','op':'gte','value':5}], 'factor':1.3})
    on_appear = {}
    if id in CALL_IDS: on_appear['callCount'] = 1
    if id in {'admission_notice','late_admission'}: on_appear['admissionCount'] = 1
    if id == 'acute_warning': on_appear['acuteChangeCount'] = 1
    events.append({'eventId':id,'title':title,'description':description,'category':category,
                   'timeRange':{'min':window[0],'max':window[1]},'conditions':conditions,
                   'weight': 1.4 if category in {'record','self'} else 1,
                   'tags':tags,'maxPerRun':1,'onAppear':on_appear,'weightModifiers':modifiers,
                   'choices':[
                       choice('careful',labels[0],f'丁寧に対応・約{detailed["durationMinutes"]}分','rest' if self_event else 'work',
                              (f'{title}に向き合い、次の仕事へ進んだ。',detailed),alt),
                       choice('quick',labels[1],f'時間を優先・約{fast["durationMinutes"]}分','work',
                              (f'{title}の要点を押さえて先へ進んだ。',fast)),
                       choice('share',labels[2],f'分担や整理・約{shared["durationMinutes"]}分',
                              'selfCare' if self_event else 'coordination',
                              (f'{title}の対応を分担し、残務を一件整理した。',shared))]})

assert len(events) == 50 and len({e['eventId'] for e in events}) == 50
assert len(RANDOM_IDS) >= 10
out = {'schemaVersion':1,'contentVersion':'official_phase3_v1','scenarioId':'day_shift','events':events}
Path('assets/content/events_phase3.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(events)} events, {len(RANDOM_IDS)} with multiple outcomes')

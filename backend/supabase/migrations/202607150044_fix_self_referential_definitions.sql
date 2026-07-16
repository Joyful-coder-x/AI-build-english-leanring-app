-- Rewrite 61 English sense definitions in the band_4_0_v1 content package that
-- accidentally used their own headword inside the definition text (e.g.
-- "father: ... a person who is acting as the father to a child"), which let
-- meaning_choice questions be answered directly from the stem without
-- knowing the word. Found by scanning definition_en for a word-boundary
-- match of the sense's own headword; each replacement was reviewed by the
-- content owner before this migration was written. A few entries also had
-- the wrong sense selected entirely (e.g. "coast" defined as a sledding
-- slope, "romantic" defined as the 19th-century arts movement) and were
-- corrected to match the existing definition_zh gloss.

begin;

update public.word_senses ws
set definition_en = v.definition_en
from (values
  ('4f6ac419-d836-541b-ae0d-76642b0975f9'::uuid, 'the female parent of a child or animal; a woman who raises a child as her own'), -- mother
  ('3020574e-73de-51f6-a10f-bc5ac51d3680'::uuid, 'the male parent of a child or animal; a man who raises a child as his own'), -- father
  ('c6e0f7e8-2f18-5d03-b237-ea25fc5107e4'::uuid, 'the sister of your father or mother, or the wife of your father''s or mother''s brother'), -- aunt
  ('0befb6d0-3c67-523f-9830-41b1ba30d733'::uuid, 'the brother of your mother or father, or the husband of your mother''s or father''s sister'), -- uncle
  ('5c515fef-fdba-5716-a3e1-f539ab48cdd9'::uuid, 'to move the corners of your mouth upward to show happiness or friendliness'), -- smile
  ('d12d2447-6bad-5894-aa41-5eb96f68c1db'::uuid, 'to have a different opinion from someone else about something'), -- disagree
  ('f339465f-0d68-51be-b427-85744f6b240c'::uuid, 'an opening in the wall or roof of a building, car, etc., usually covered with a sheet of glass, that lets in light and air and lets people see outside'), -- window
  ('821d3dbb-8437-5380-ab95-e010784c056b'::uuid, 'a lamp or other device that produces brightness so people can see'), -- light
  ('ac727e9c-e501-5d2a-8ded-2633e9cad846'::uuid, 'a set of steps that lead from one level of a building to another'), -- stairs
  ('29c332d7-3a49-5787-9d57-768be089b097'::uuid, 'a small drinking container made of a hard, transparent material'), -- glass
  ('b7071f8c-ce9f-5ecd-94ad-733003e2bbf9'::uuid, 'different from what is usual; not ordinary'), -- special
  ('8f9155dc-363f-5a34-9786-92db2dd97fbd'::uuid, 'the warmest season of the year, between spring and autumn'), -- summer
  ('061a782a-4588-517e-a9f0-b24e511fa006'::uuid, 'a journey made by air, especially in an airplane'), -- flight
  ('c9f19186-edd6-5642-bdba-e13df801f3af'::uuid, 'a hot drink made by pouring boiling water over the dried leaves of a particular plant'), -- tea
  ('ed6fb694-d4a6-53cb-be2d-456c382c9770'::uuid, 'a round vegetable made up of layers, with a strong smell and taste, often used in cooking'), -- onion
  ('75a86705-8a14-52c6-b246-ac5cd3db4500'::uuid, 'the sense that lets you notice the flavor of food or drink using your tongue'), -- taste
  ('9b6f95b2-e181-5926-8fc8-7c89dc2e0727'::uuid, 'a hot drink made from the roasted and ground beans of a tropical plant'), -- coffee
  ('b618b2ef-1716-50d9-a942-a8cf3fe273a1'::uuid, 'an area of land, together with its buildings, used for growing crops or raising animals'), -- farm
  ('f939b31a-66c3-593d-9e0c-b81d009983bd'::uuid, 'coming after the fourth item or position in a sequence; 5th'), -- fifth
  ('1c70a19c-8aac-5250-b086-cb5d43ab4e2b'::uuid, 'a small oval fruit that grows on a Mediterranean tree, eaten as food or pressed to make cooking oil'), -- olive
  ('a9d79d7c-8324-5ff3-8175-910dc4f10eb2'::uuid, 'the activity or sport of moving through water using your arms and legs'), -- swimming
  ('2b32d342-8725-5038-af81-5de6e0da4f49'::uuid, 'an adult female farm animal kept for its milk or meat'), -- cow
  ('5fd01b4b-3360-5db9-8445-c113ce428e1f'::uuid, 'the meat of a common farm bird, eaten as food'), -- chicken
  ('ffb22291-f56d-5738-9ea9-e9b8878b6cb1'::uuid, 'the coldest season of the year, between autumn and spring'), -- winter
  ('11bb3b28-49db-57aa-b5ec-aecdad952d50'::uuid, 'going far down from the top or surface; (of a feeling) very strong or intense'), -- deep
  ('22d9ed40-3128-51a9-a59b-eb54a9ea1c00'::uuid, 'in, at, or to all places'), -- everywhere
  ('aa86c7a3-50e2-5906-9895-331e70d50714'::uuid, 'in, at, or to a place that is not specified or known'), -- somewhere
  ('0d7f6a95-b641-5850-ae59-e26df8435e4c'::uuid, 'to copy a file or program from the internet or another computer onto your own device'), -- download
  ('dc878851-ec74-5717-9c8a-67b20caf146f'::uuid, 'a team sport in which players use curved sticks to hit a small ball or puck into the other team''s goal'), -- hockey
  ('05704a64-a51a-5e9a-9fbe-e6217a75bce6'::uuid, 'the activity of making music with your voice'), -- singing
  ('d066bf0b-5c77-5f3c-933c-7c6ecc3595b9'::uuid, 'to create or put together something, such as a structure or a system'), -- build
  ('0266f08a-e8f5-561e-aa1f-a7eae171c15d'::uuid, 'having a low temperature; not warm'), -- cold
  ('be5fd954-712e-5b04-9b78-060ad2507509'::uuid, 'relating to love or a loving relationship; showing strong feelings of love'), -- romantic
  ('ab598b32-b9c9-50f6-8760-4ce7ed79b4b6'::uuid, 'to decide which thing or person you want from two or more options'), -- choose
  ('a05961bc-d919-5184-a635-74da22c684da'::uuid, 'a rise in the amount, size, or number of something'), -- increase
  ('3a582e8c-6c68-513b-b8f2-f3c4932b542b'::uuid, 'to reach a place, especially at the end of a journey'), -- arrive
  ('f417a667-33dc-5654-baa1-b26f7790e3d7'::uuid, 'used to say that something is true or will happen regardless of what was just said'), -- anyway
  ('38c72d3c-8ea3-533a-a906-9add7dec374c'::uuid, 'in, at, or to any place'), -- anywhere
  ('12c156c7-adc2-551e-943b-94424d633a29'::uuid, 'exactly alike; not different'), -- same
  ('4372f459-fb22-5b6e-9abf-ceb50cd9d956'::uuid, 'a place of higher education where students study for degrees'), -- university
  ('b814b373-5593-5552-8a65-912b9886f323'::uuid, 'used to point to a specific person, thing, or idea that is nearby or has just been mentioned'), -- this
  ('ad45d03e-ee2c-5e97-80e4-24563013e992'::uuid, 'supporting the idea that a country should be governed by elected representatives instead of a king or queen'), -- republican
  ('654db93c-0f9b-5f86-8ced-366cc928db1b'::uuid, 'suitable for official or serious occasions; following accepted rules of style or behavior'), -- formal
  ('d072934f-a53a-5de9-a99c-669edeb39279'::uuid, 'the best possible; exactly right for a particular purpose'), -- ideal
  ('3b282778-5cbe-5520-98ce-bd79b598e105'::uuid, 'a way of solving a problem; (in chemistry) a liquid in which another substance is fully dissolved'), -- solution
  ('66b6a915-5702-5bb0-94e8-aead8a01805e'::uuid, 'the power and strength needed for physical or mental activity; (in science) the ability to do work'), -- energy
  ('f5aba3e8-b23d-5098-84f2-097706260bed'::uuid, 'a written or other account of facts or events, kept for future reference'), -- record
  ('b81ef277-e8e4-5f2c-90e8-c1af4fd6d66f'::uuid, 'a soft white fiber that grows around the seeds of a particular plant, used to make cloth'), -- cotton
  ('83c62c5e-806b-5e50-a9b8-8e650a85f7ef'::uuid, 'to try to win or do better than other people in a contest, game, or activity'), -- compete
  ('5adfd81e-87f8-5707-9d14-34577bf58060'::uuid, 'used to say that one thing is preferred, true, or done instead of another'), -- rather
  ('d3f7f6a5-613e-55b7-b1f6-2fdf09d79bfa'::uuid, 'to arrive at or get to a place, level, or amount'), -- reach
  ('ba51efb9-1e4a-552f-920e-f2a7e55405ae'::uuid, 'a letter or group of letters added to the end of a word'), -- ending
  ('4a05fc58-4fba-58e8-b8c6-6b002b3c7704'::uuid, 'to have or keep something in your hand or arms'), -- hold
  ('53c564c0-5a9b-5221-baf8-79d4d0dbab7c'::uuid, 'without difficulty; in a simple way'), -- easily
  ('13d5967a-67ec-567c-a559-1d200d07b357'::uuid, 'to not succeed in doing something you tried or were expected to do'), -- fail
  ('f03e8113-b4f3-58a8-9f13-ae75c845cc8c'::uuid, 'to keep happening, existing, or doing something without stopping'), -- continue
  ('53c7ab70-b190-556a-b5ce-65beb688b118'::uuid, 'the land that is next to or close to the sea'), -- coast
  ('3dc2d549-f823-540f-a8fa-c6baf30aa3ca'::uuid, 'to say a word or sound in a particular way'), -- pronounce
  ('4cab1b2f-5fa0-5b34-9598-1ece56cc185e'::uuid, 'at a slow speed; not quickly'), -- slowly
  ('b0ae1a8c-18e1-54aa-b385-6a79a2d28714'::uuid, 'to take something away from a place or position'), -- remove
  ('2e2092eb-bd16-578c-9ecb-b7a0df2f77a0'::uuid, 'to say or do something as a reaction to something else') -- respond
) as v(sense_id, definition_en)
where ws.id = v.sense_id;

commit;

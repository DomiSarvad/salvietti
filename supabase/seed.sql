-- =====================================================================
-- SEED — datos reales tomados de los inventarios de planta (26/05/2026)
-- Ejecutar DESPUÉS de schema.sql
-- =====================================================================

-- TAPAS / CÁPSULAS
insert into public.tapas (detalle, formato, color, unidad_medida, cantidad_sistema, cantidad_real, unidades_por_caja, stock_minimo) values
('Capsulas PET','Long Finish','Transparente','PZA',0,0,4500,3000),
('Capsulas PET','Long Finish','Blanco','PZA',0,0,5000,3000),
('Capsulas PET','Short Finish','Transparente','PZA',39350,32650,5500,10000),
('Capsulas PET','Short Finish','Verde','PZA',361800,470900,6700,10000),
('Capsulas PET','Long Finish','Verde','PZA',155250,155250,6700,10000),
('Capsulas PET','Long Finish','Negro','PZA',100,100,4500,500),
('Capsulas PET','Short Finish','Negro','PZA',13400,10050,5000,3000),
('Capsulas PET','Long Finish','Dorado','PZA',2500,2500,6700,1000),
('Capsulas PET','Long Finish','Rojo','PZA',0,0,5000,1000),
('Capsulas PET','Short Finish','Rojo','PZA',134000,550700,5000,10000),
('Capsulas PET OBSERVADO','Short Finish','Amarillo',' PZA',0,0,6700,1000),
('Capsulas PET','Short Finish','Amarillo','PZA',10400,10400,5600,5000),
('Capsulas PET','Long Finish','Amarillo','PZA',63390,63390,5200,10000),
('Tapa Corona','Long Finish','Azul','PZA',12500,12500,5000,5000),
('Tapa Botellón 20 lt','Tapa Corona','N/a','PZA',130000,90000,5000,10000);

-- PREFORMAS
insert into public.preformas (detalle, formato, tamano, unidad_medida, cantidad_sistema, cantidad_real, unidades_por_caja, stock_minimo) values
('Preforma de 54.7gr','Short','2,5 L','UN',0,0,7479.75,5000),
('Preforma de 54.6gr','Short','2,5 L','UN',0,0,7488,5000),
('Preforma de 52.65gr','Short','2,5 L','UN',0,0,7056,5000),
('Preforma de 50.8gr','Short','2,5 L','UN',112608,197030,7036.8,10000),
('Preforma de 47gr','Long','2 L','UN',0,200629,8723,10000);

-- MATERIA PRIMA (kg salvo indicado)
insert into public.materia_prima (detalle, unidad_medida, cantidad_sistema, cantidad_real, tipo_envase, cantidad_por_envase, proveedor_habitual, consumo_promedio_dia, stock_minimo) values
('AZUCAR','KG',56212.00,46967.00,'quintal',46.0,'San Aurelio',2500,20000),
('ESENCIA DE NARANJA','KG',47.50,81.30,'bidon',20.0,'Sapore y Naturex',12.4,20),
('ESENCIA DE LIMA LIMON','KG',0.48,0.48,'bidon',15.0,'Sapore',2.5,10),
('ESENCIA DE PIÑA','KG',8.80,8.80,'bidon',15.0,'Sapore',4.0,10),
('ESENCIA DE GRANADINA','KG',22.44,33.11,'bidon',15.0,'Sapore',2.2,10),
('ESENCIA DE POMELO','KG',25.30,24.91,'bidon',15.0,'Sapore',6.5,10),
('ESENCIA DE GINGER ALE','KG',4.10,15.20,'bidon',20.0,'Sapore',7.8,10),
('ESENCIA DE KINOTTO CHEPE','KG',10.59,5.89,'bidon',15.0,'Sapore',4.7,10),
('ESENCIA DE KINOTTO COLA','KG',14.58,54.58,'bidon',20.0,'Sapore',9.4,10),
('ESENCIA DE PAPAYA (SAPORE)','KG',835.50,832.20,'bidon',20.0,'Sapore',14.7,20),
('ESENCIA DE ARANDANO','KG',24.42,78.36,'bidon',25.0,'Sapore',14.7,10),
('ESENCIA DE FRAMBUESA','KG',2.36,1.96,'bidon',20.0,'IFF',0.3,5),
('ESENCIA DE KIWI','KG',0.87,0.53,'bidon',5.0,'Sapore',0.4,5),
('ESENCIA DE TUMBO','KG',0.71,0.52,'bidon',5.0,'Sapore',0.3,5),
('ESENCIA DE FRUTILLA','KG',13.05,12.58,'bidon',5.0,'Sapore',1.9,5),
('ACIDO CITRICO','KG',4.70,4.51,'bidon',15.0,'Sapore',0.3,10),
('CITRATO DE SODIO','KG',598.68,936.11,'bidon',15.0,'Sapore',40,50),
('BENZOATO DE SODIO (AMERICANO)','KG',29.05,28.66,'bolsa',15.0,'Sapore',2.7,10),
('BENZOATO DE SODIO (CHINO)','KG',158.49,158.49,'bolsa',25.0,'Alemcorp/Hiper sabor',9,20),
('CAFEINA ANHIDRIDA','KG',185.49,174.10,'bolsa',25.0,'Maprial',9,20),
('COLOR AMARANTO','KG',36.31,35.81,'bolsa',25.0,'Maprial',1,5),
('ACIDO FOSFORICO','KG',6.28,5.42,'carton',25.0,'Maprial',0.3,5);

-- FÓRMULAS DE EJEMPLO (rendimiento por lote de 100 L) — el jefe de
-- producción debe ajustarlas a la receta real exacta de Salvietti.
insert into public.formulas (sabor, rendimiento_litros) values
('Naranja',100), ('Lima Limón',100), ('Piña o Anana',100), ('Granadina',100);

insert into public.formula_detalle (formula_id, materia_prima_id, cantidad_por_lote)
select f.id, m.id, v.cant
from (values
  ('Naranja','AZUCAR',10.5),('Naranja','ESENCIA DE NARANJA',1.2),
  ('Naranja','ACIDO CITRICO',0.2),('Naranja','CITRATO DE SODIO',0.3),
  ('Lima Limón','AZUCAR',10.5),('Lima Limón','ESENCIA DE LIMA LIMON',1.0),
  ('Lima Limón','ACIDO CITRICO',0.25),
  ('Piña o Anana','AZUCAR',10.5),('Piña o Anana','ESENCIA DE PIÑA',1.1),
  ('Granadina','AZUCAR',10.5),('Granadina','ESENCIA DE GRANADINA',1.0)
) as v(sabor, mp, cant)
join public.formulas f on f.sabor = v.sabor
join public.materia_prima m on m.detalle = v.mp;

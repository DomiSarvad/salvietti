-- =====================================================================
-- SALVIETTI CONTROL — v38: Informe general de Producción (Módulo 11,
-- segunda parte). Ejecutar DESPUÉS de schema_v37_recetas_doble_aprobacion.sql
-- (y de haberla vuelto a ejecutar, porque toca `mermas_consolidado`).
-- Se puede volver a ejecutar sin problema.
-- =====================================================================
--
-- Sección 8 del md: "Resumen de Producción, con detalle por área al hacer
-- clic. Compara cada preparado real contra el estándar de su sabor (papaya
-- = 12 cajas), muestra la desviación, la atribuye al área según el motivo
-- registrado y marca en alerta lo que supere el 3 % de merma."
--
-- No hace falta una tabla nueva: todo lo que compara ya se registró en
-- módulos anteriores. Este archivo solo agrega la vista que lo junta:
--
--   * Esperado  : de `jarabes_preparados` (cantidad de preparados) ×
--                 `sabores.estandar_cajas` — lo que ESE sabor debería dar.
--   * Producido : de `salidas_reporte_detalle` (Módulo 8), convertido a
--                 cajas con `presentaciones.unidades_por_caja`.
--   * Desviación: producido − esperado (positivo = se produjo de más).
--   * Merma     : el detalle por área ya está en `mermas_consolidado`
--                 (Módulo 9); la pantalla lo filtra por fecha y sabor
--                 cuando el Gerente hace clic en una fila — no hace falta
--                 otra vista para eso.
--
-- APROXIMACIÓN A VALIDAR CON GERENCIA: se compara por fecha exacta (el día
-- que se preparó el jarabe contra el día que salió embotellado). En la
-- práctica el jarabe de un día puede embotellarse otro día distinto; si
-- eso pasa seguido, esta comparación por fecha se va a tener que ajustar
-- (por ejemplo, a una ventana de varios días) una vez que Producción lo
-- confirme. Además, "producido" solo cuenta lo que tiene la equivalencia
-- de cajas cargada (dato pendiente para algunas presentaciones, sección 13);
-- `datos_incompletos` avisa cuándo el número puede estar de menos por eso.

create or replace view public.informe_produccion_resumen with (security_invoker = true) as
    with esperado as (
        select p.fecha, p.sabor_id, s.nombre as sabor,
               sum(p.cantidad_preparados) as preparados,
               sum(p.cantidad_preparados * s.estandar_cajas) as cajas_esperadas
          from public.jarabes_preparados p
          join public.sabores s on s.id = p.sabor_id
         where p.estado = 'finalizada'
         group by p.fecha, p.sabor_id, s.nombre
    ),
    producido as (
        select d.fecha, d.sabor_id,
               sum(case when pr.unidades_por_caja > 0 then d.total_botellas / pr.unidades_por_caja end)
                   as cajas_producidas,
               bool_or(d.total_botellas is null or coalesce(pr.unidades_por_caja, 0) = 0)
                   as datos_incompletos
          from public.salidas_reporte_detalle d
          join public.presentaciones pr on pr.id = d.presentacion_id
         group by d.fecha, d.sabor_id
    )
    select coalesce(e.fecha, pr.fecha) as fecha,
           coalesce(e.sabor_id, pr.sabor_id) as sabor_id,
           coalesce(e.sabor, s2.nombre) as sabor,
           e.preparados,
           e.cajas_esperadas,
           pr.cajas_producidas,
           case when e.cajas_esperadas > 0 and pr.cajas_producidas is not null
                then round(pr.cajas_producidas - e.cajas_esperadas, 2)
           end as desviacion_cajas,
           case when e.cajas_esperadas > 0 and pr.cajas_producidas is not null and e.cajas_esperadas > 0
                then round(100 * (pr.cajas_producidas - e.cajas_esperadas) / e.cajas_esperadas, 1)
           end as desviacion_porcentaje,
           coalesce(pr.datos_incompletos, false) as datos_incompletos
      from esperado e
      full outer join producido pr on pr.fecha = e.fecha and pr.sabor_id = e.sabor_id
      left join public.sabores s2 on s2.id = pr.sabor_id
     order by fecha desc, sabor;

grant select on public.informe_produccion_resumen to authenticated;

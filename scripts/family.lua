local utils = require 'utils'

function get_historical_dwarves()
    local HistoricalDwarves = {}
    dwarf_race = df.global.ui.race_id
    --race = df.creature_raw.find(fig.race)
    figures = df.global.world.history.figures
    for i,fig in ipairs(figures) do
        if fig.race == dwarf_race then
            table.insert(HistoricalDwarves, fig)
        end
    end
    return HistoricalDwarves
end

function get_name_unit(unit, in_english)
    in_english = in_english or false
    lang = dfhack.units.getVisibleName(unit)
    return dfhack.TranslateName(lang, in_english)
end

function get_name_hfig(hfig, in_english)
    in_english = in_english or false
    return dfhack.TranslateName(hfig.name, in_english)
end

function unit_to_histfig(unit)
    if unit and unit.hist_figure_id then
        return utils.binsearch(df.global.world.history.figures, unit.hist_figure_id, 'id')
    end
    return nil
end

function get_caste_name(race, caste, profession)
    return dfhack.units.getCasteProfessionName(race, caste, profession)
end

function gender_sym(sex)
    if sex == 0 then
        return  "♀"
    elseif sex == 1 then
        return "♂"
    end
    return "⚪"

end

function gender_read(sex)
    if sex == 0 then
        return  "female"
    elseif sex == 1 then
        return "male"
    end
    return "unknown"

end

function get_relationships(hfig)
    local relations = {
        mothers = {},
        fathers = {},
        spouses = {},
        children = {},
    }
    for _,link in ipairs(hfig.histfig_links) do
        if link:getType() == df.histfig_hf_link_type.MOTHER then
            table.insert(relations.mothers, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.FATHER then
            table.insert(relations.fathers, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.SPOUSE then
            table.insert(relations.spouses, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.CHILD then
            table.insert(relations.children, link.target_hf)
        else
            --print("got unknown link: ", link:getType())
        end
    end

    -- cleanup mothers, fathers, and spouses for usability
    if #relations.mothers == 1 then
        relations.mother = relations.mothers[1]
    end
    if #relations.fathers== 1 then
        relations.father= relations.fathers[1]
    end
    if #relations.spouses == 1 then
        relations.spouse = relations.spouses[1]
    end

    return relations
end

function get_hfig(hf_id)
    return utils.binsearch(df.global.world.history.figures, hf_id, 'id')
end

function get_events_for_hfigs(hfig_ids)
    local events = {}
    for _,event in ipairs(df.global.world.history.events) do
        for _,hf_id in ipairs(hfig_ids) do
            if event:isRelatedToHistfigID(hf_id) then
                context = df.history_event_context:new()
                sentence = dfhack.with_temp_object(
                    df.new "string",
                    function(str)
                        event:getSentence(str, context, 1, 0)
                        return str.value
                    end
                )
                phrase = dfhack.with_temp_object(
                    df.new "string",
                    function(str)
                        event:getPhrase(str, context, 1, 0)
                        return str.value
                    end
                )
                df.delete(context)
                if events[hf_id] == nil then
                    events[hf_id] = {}
                end
                if sentence~= nil and phrase ~= nil then
                    table.insert(events[hf_id], { ['id'] = event.id, ['type'] = event:getType(), ['year'] = event.year, ['description'] = sentence, ['phrase'] = phrase })
                end
            end
        end
    end
    return events
end

function write_csv(family)
--- writes out the list of dwarves in the CSV format used by GRAMPS
-- http://www.gramps-project.org/wiki/index.php?title=Gramps_3.2_Wiki_Manual_-_Manage_Family_Trees:_CSV_Import_and_Export

    local Person = {}
    local person_header = "Person,Surname,Given,Callname,Title,Gender,Birth date,Death date,deathcause,Note,\n"
    local Marriage = {}
    local marriage_header = "Marriage,Husband,Wife,Date,Note\n"
    local Family = {}
    local family_header = "Family,Child\n"

    local events = get_events_for_hfigs(family)
    local marriage = nil

    for _,hf_id in ipairs(family) do
        local dwarf = get_dwarf(get_hfig(hf_id))
        local given, surname= string.match(dwarf.name, "(%S+)%s+(%S+)")
        local note = 'These notable events are associated with this dwarf:\n'
        local deathcause = ''
        if events[hf_id] ~= nil then
            for _,event in ipairs(events[hf_id]) do
                if event.type ==  df.history_event_type.HIST_FIGURE_DIED then
                    deathcause = event.description
                elseif event.type ==  df.history_event_type.ADD_HF_HF_LINK then
                    if string.find(event.description, "married") ~= nil then
                        marriage = event
                    end
                end
                note = note .. '\n' ..event.description
            end
        end
        Person[dwarf.hfid] = string.format('[%s],%s,%s,%s,%s,%s,%s,%s,"%s","%s",\n', dwarf.hfid, surname, given, dwarf.translated_name, dwarf.caste, gender_read(dwarf.sex), dwarf.birth_year, dwarf.death_year, deathcause, note)

        for _,spouse in ipairs(dwarf.relations.spouses) do
            local husband = dwarf.hfid
            local wife = spouse
            if dwarf.sex == 0 then
                husband = spouse
                wife = dwarf.hfid
            end
            fid = string.format("%d%d", husband, wife)

            Marriage[fid] = string.format('[%s],[%s],[%s],%s,"%s"\n', fid, husband, wife, marriage.year or '', marriage.description or '')
        end

        local father = dwarf.relations.fathers[1]
        local mother = dwarf.relations.mothers[1]
        if father and mother then
            local husband = father
            local wife = mother
            local fid = string.format("%d%d", husband, wife)
            local mid = string.format("%s%s%s", father, mother, dwarf.hfid)

            Marriage[fid] = string.format('[%s],[%s],[%s],%s,"%s"\n', fid, husband, wife, marriage.year or '', marriage.description or '')
            Family[mid] = string.format("[%s],[%s]\n", fid, dwarf.hfid)
        end

        for _,child_id in ipairs(dwarf.relations.children) do
            -- the child may be in the family but outside the scope of the original search
            local is_in_tree = utils.binsearch(family, child_id, nil) ~= nil
            if not is_in_tree then goto continue end
            child = get_hfig(child_id)
            if child then
                -- if there ever actually is more than one mother and father
                -- how would we know from which relationship the child comes from?
                local relations = get_relationships(child)
                local father = relations.father
                local mother = relations.mother
                if father or mother then
                    -- we save the relation even if a parent is missing
                    local mid = string.format("%s%s%s", father, mother, child_id)
                    local fid = string.format("%s%s", father, mother)
                    Family[mid] = string.format("[%s],[%s]\n", fid, child_id)
                end
            end
            ::continue::
        end
    end

    local f = io.open("family.csv", "w")

    f:write(person_header)
    for _,p in pairs(Person) do
        f:write(p)
    end
    f:write('\n')
    f:write(marriage_header)
    for _,m in pairs(Marriage) do
        f:write(m)
    end
    f:write('\n')
    f:write(family_header)
    for _,m in pairs(Family) do
        f:write(m)
    end

    f:close()
    print("Wrote family.csv")
end

function get_dwarf(hfig)
--- plain text version of the unit
    if not hfig then
        return nil
    end

    local name = get_name_hfig(hfig)
    local eng_name = get_name_hfig(hfig, true)
    local birth_year = hfig.born_year

    local death_year = hfig.died_year
    if death_year == -1 then
        death_year = ''
    end

    local caste = get_caste_name(hfig.race, hfig.caste, hfig.profession)

    local relations = {
        mothers = {},
        fathers = {},
        spouses = {},
        children = {}
    }
    for _,link in ipairs(hfig.histfig_links) do
        if link:getType() == df.histfig_hf_link_type.MOTHER then
            table.insert(relations.mothers, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.FATHER then
            table.insert(relations.fathers, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.SPOUSE then
            table.insert(relations.spouses, link.target_hf)
        elseif link:getType() == df.histfig_hf_link_type.CHILD then
            table.insert(relations.children, link.target_hf)
        else
            --print("got unknown link: ", link:getType())
        end
    end

    local d= {
        ['uid'] = hfig.unit_id,
        ['hfid'] = hfig.id,
        ['name'] = name,
        ['translated_name'] = eng_name,
        ['sex'] = hfig.sex,
        ['birth_year'] = birth_year,
        ['death_year'] = death_year,
        ['caste'] = caste,
        ['relations'] = relations,
        --[''] = ,
    }
    return d
end

function wrap(id, gen)
    return {['id'] = id, ['gen'] = gen}
end

function crawl_family(hf_id, max_generations, max_spouse_branches)
--- Breadth first search of hf_id's relations
--- the depth is capped at max_generations
--- branching off into spouses/in-laws is capped at max_spouse_branches
--- Returns a list of all the dwarves found
    local max_generations = max_generations or 5
    local max_spouse_branches = max_spouse_branches or 0
    local spouse_gen = max_generations - max_spouse_branches
    local members = {}
    local queue = {}
    -- nil = unseen, false = queued, true = visted
    local visited = {}
    local MAX = 10000 -- prevent very long running ops
    local counter = 0

    function _is_unqueued(_id)
        return _id ~= nil and visited[_id] == nil
    end

    function _visit_relation(rid, new_gen)
        if _is_unqueued(rid) then
            queue[#queue+1] = wrap(rid, new_gen)
            visited[rid] = false
        end
    end

    queue[1] = wrap(hf_id, 0) -- starting dwarf is generation 0
    while counter < MAX and #queue > 0 do
        counter = counter+1
        local node = queue[1]
        table.remove(queue, 1)
        visited[node.id] = true

        local hfig = utils.binsearch(df.global.world.history.figures, node.id, 'id')

        if node.gen < max_generations then
            for _,link in ipairs(hfig.histfig_links) do
                    if link:getType() == df.histfig_hf_link_type.MOTHER or
                       link:getType() == df.histfig_hf_link_type.FATHER or
                       link:getType() == df.histfig_hf_link_type.CHILD
                       then
                        _visit_relation(link.target_hf, node.gen+1)
                    elseif link:getType() == df.histfig_hf_link_type.SPOUSE then
                        _visit_relation(link.target_hf, spouse_gen)
                    end
            end
        end
        members[#members+1] = node.id
    end

    return members
end

function family()
    local unit = dfhack.gui.getSelectedUnit()
    if dfhack.units.isDwarf(unit) then
        local hfig = unit_to_histfig(unit)
    end

    local family_members = crawl_family(unit.hist_figure_id)
    print(get_name_unit(unit) .. " has ".. #family_members .. " family members")
    write_csv(family_members)
end

family()


-- План счетов бухгалтерского учета по МСФО
INSERT INTO public.dct_accounts(account_id, parent_account_id, account_description) VALUES
('1',    null, 'Счета учета внеоборотных активов (non-current assets)'),
('1.1',    '1', 'Основные средства'),
('1.3',    '1', 'Инвестиционное имущество'),
('1.5',    '1', 'Гудвил'),
('1.4',    '1', 'Нематериальные активы, кроме гудвила'),
('1.58.1', '1', 'Инвестиции, учитываемые долевым методом'),
('1.58.2', '1', 'Инвестиции в дочерние, совместные и ассоциированные компании'),
('1.11',   '1', 'Внеоборотные биологические активы'),
('1.62.1', '1', 'Долгосрочная дебиторская задолженность'),
('1.10',   '1', 'Внеоборотные запасы'),
('1.9',    '1', 'Отложенные налоговые активы'),
('1.62.2', '1', 'Долгосрочная дебиторская задолженность по текущему налогу'),
('1.6',    '1', 'Прочие внеоборотные финансовые активы'),
('1.7',    '1', 'Прочие внеоборотные нефинансовые активы'),
('1.8',    '1', 'Внеоборотные неденежные активы, находящиеся в залоге, которыми залогодержатель вправе распоряжаться'),
('2',    null, 'Счета учета оборотных активов (current assets)'),
('2.10',    '2', 'Оборотные запасы'),
('2.62',    '2', 'Краткосрочная дебиторская задолженность'),
('2.63',    '2', 'Краткосрочная дебиторская задолженность по текущему налогу'),
('2.11',    '2', 'Оборотные биологические активы'),
('2.16',    '2', 'Прочие оборотные финансовые активы'),
('2.17',    '2', 'Прочие краткосрочные нефинансовые активы'),
('2.51',    '2', 'Денежные средства и эквиваленты денежных средств'),
('2.52',    '2', 'Оборотные неденежные активы, находящиеся в залоге, которыми залогодержатель праве распоряжаться'),
('2.47',    '2', 'Внеоборотные активы и группы выбытия для продажи или передачи собственникам'),
('3',    null, 'Счета учета капитала (equity)'),
('3.80',    '3', 'Акционерный (уставный) капитал'),
('3.84',    '3', 'Нераспределенная прибыль'),
('3.83',    '3', 'Эмиссионный доход'),
('3.81',    '3', 'Собственные акции, выкупленные у акционеров'),
('3.89',    '3', 'Прочий капитал организации'),
('3.82',    '3', 'Прочий резервный капитал'),
('3.85',    '3', 'Неконтролируемые доли'),
('4',    null, 'Счета учета долгосрочных обязательств (non-current liabilities)'),
('4.72',    '4', 'Долгосрочные резервы на вознаграждения работников'),
('4.74',    '4', 'Прочие долгосрочные резервы'),
('4.60',    '4', 'Долгосрочная кредиторская задолженность'),
('4.77',    '4', 'Отложенные налоговые обязательства'),
('4.68',    '4', 'Долгосрочная задолженность по текущему налогу'),
('4.66',    '4', 'Прочие долгосрочные финансовые обязательства'),
('4.78',    '4', 'Прочие долгосрочные нефинансовые обязательства'),
('5',    null, 'Счета учета краткосрочных обязательств (current liabilities)'),
('5.73',    '5', 'Краткосрочные резервы на вознаграждения работников'),
('5.75',    '5', 'Прочие краткосрочные резервы'),
('5.60',    '5', 'Краткосрочная кредиторская задолженность'),
('5.68',    '5', 'Краткосрочные обязательства по текущему налогу'),
('5.67',    '5', 'Прочие краткосрочные финансовые обязательства'),
('5.79',    '5', 'Прочие краткосрочные нефинансовые обязательства'),
('6',    null, 'Счета учета совокупных доходов (comprehensive income)'),
('6.90.1',  '6', 'Выручка'),
('6.90.2',  '6', 'Себестоимость продаж'),
('6.91.1',  '6', 'Прочие доходы'),
('6.90.44', '6', 'Коммерческие расходы'),
('6.90.26', '6', 'Управленческие расходы'),
('6.91.2',  '6', 'Прочие расходы'),
('6.91.9',  '6', 'Прочие прибыли (убытки)'),
('6.91.4',  '6', 'Финансовые доходы'),
('6.91.3',  '6', 'Расходы на финансирование'),
('6.91.41', '6', 'Доля прибыли (убытка) ассоциированных компаний и совместных предприятий, учтенная долевым методом'),
('6.99.1',  '6', 'Расходы по налогу на прибыль (по продолжающейся деятельности)'),
('6.91.6',  '6', 'Прибыль (убыток) от прекращаемой деятельности'),
('7',    null, 'Счета учета прочих совокупных доходов (other comprehensive income)'),
('7.91.4',  '7', 'Прочие совокупные доходы от курсовых разниц при пересчете (до налогообложения)'),
('7.91.5',  '7', 'Прочие совокупные доходы по финансовым активам, имеющимся в наличии для продажи (до налогообложения)'),
('7.91.6',  '7', 'Прочие совокупные доходы от хеджирования денежных потоков'),
('7.91.7',  '7', 'Прочие совокупные доходы - прибыли (убытки) от переоценки'),
('7.91.8',  '7', 'Прочие совокупные доходы - актуарные прибыли (убытки) по пенсионным планам с установленными выплатами'),
('7.91.42', '7', 'Доля прочих совокупных доходов ассоциированных компаний и совместных предприятий, учтенных долевым методом'),
('8',    null, 'Управленческий учёт'),
('9',    null, 'Забаланс')
;

/*
finance=# select count(*) from dct_accounts;
 count 
-------
    70
(1 row)
*/
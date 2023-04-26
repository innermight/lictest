#Импортируем модули для корректной работы
Import-Module ActiveDirectory
Import-Module PoshRSJob

#В переменную $comp забираем все компьютеры из AD, но в алфавитном порядке и включенные
$comp=@(Get-ADComputer -Filter {Enabled -eq "true"} | Sort Name | % {$_.name})

#Основа скрипта. Функция которая сможет обратиться ко всему парку компьютеров одновременно, а полученные результаты записать в таблицу
function Ping-Computer {
    param($comp)

#Отправляем на каждый компьютер 1 пакет пинга для проверки включенности/выключенности компьютера
    if (Test-Connection $comp -Count 1 -Quiet) {
#Так как подразумеваем наличие в сети устройств на Windows7, то используем более короткий вариант Get-WmiObject для получения статуса активации
        $license = Gwmi SoftwareLicensingProduct -comp $comp | where {$_.LicenseStatus} | % {$_.LicenseStatus}
#Состояние лицензии отображается в виде числа от 1 до 6, поэтому для удобства чтения преобразуем цифры в буквы
        $licTXT = @()
        foreach ($lic in $license) {
            switch ($lic) {
            0 { $licTXT += "Активация отсутствует" }
            1 { $licTXT += "Активация выполнена" }
            2 { $licTXT += "Отсутствует ключ лицензии" }
            3 { $licTXT += "Требуется активация" }
            4 { $licTXT += "Истек срок действия лицензии" }
            5 { $licTXT += "Предупреждение о необходимости активации" }
            6 { $licTXT += "Расширенный период использования без лицензии" }
            default { $licTXT += "Неизвестно" }
            }
        }
#Может случиться так, что в Windows будет несколько статусов лицензирования, поэтому объединяем их в одну строку
        $licTXT = $licTXT -join ", "
#В переменную $os забираем 2 значения. А именно версию Windows и сам билд, который поможет нам понять как давно небыло обновлений
        $os = Gwmi Win32_OperatingSystem -comp $comp -Property Caption, Version  
#Заполняем таблицу GridView полученными данными
        [PSCustomObject] @{
            Computer = $comp
            Ping = "В сети"
            LicenseStatus = $licTXT
            WinVer = $os.Caption
            WinBuild = $os.Version
#Смотрим как давно компьютер последний раз появлялся в сети. Тут нам это сильно не нужно, но в случае, если он выключен, позволит понять как давно он потерялся
            LastLogonDate = Get-ADComputer $comp -property * | % {$_.LastLogonDate}
        }
    } else {
#В случае, если компьютер не ответил на пинг, то в таблицу пишем его имя, состояние, когда был последний раз в сети, а остальное прочерки
        [PSCustomObject] @{
            Computer = $comp
            Ping = "НЕ В СЕТИ"
            LicenseStatus = "-"
            WinVer = "-"
            WinBuild = "-"
#А вот тут уже нам полезно знать когда там последний раз включали компьютер
            LastLogonDate = Get-ADComputer $comp -property * | % {$_.LastLogonDate}
        }
    }
}

#Задача, которая как раз за счет вышеописанной функции, позволит нам собрать информацию со всех компьютеров разом + заполнит итоговую таблицу
$tasks = @()
foreach ($computer in $comp) {
    $tasks += Start-RSJob -Name $computer -ScriptBlock ([ScriptBlock]::Create((Get-Command Ping-Computer).ScriptBlock)) -ArgumentList $computer
}

#Ожидаем, когда закончится обработка всех задач
Wait-RSJob -Job $tasks

$results = Receive-RSJob -Job $tasks

#Выводим данные в таблицу
$results | Select-Object Computer, Ping, LastLogonDate, LicenseStatus, WinVer, WinBuild | Out-GridView
#Выдерживаем паузу дабы по итогу таблица оставалась видимой
pause

#По желанию вывод можно переделать на таблицу в CSV
#В случае, если на пользовательских компьютерах будет бунтовать брандмауэр и антивирус, или не будет настроен RPC, будут ошибки в WMI запросах. Это нормально, и в рамках данного скрипта не решаемо.
#Также нужно понимать, что в данном скрипте, с целью экономии времени используется многопоточность. Поэтому из расчета на 100 компьютеров он съедает примерно 4GB оперативной памяти, но длится это не долго. Примерно 2 - 3 минуты